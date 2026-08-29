#!/usr/bin/env bash
#
# Serverless GPU endpoints (BYO-container).
#
# An endpoint is an autoscaling pool of worker containers running your image:
# Novita schedules workers per the worker_config, scales on the policy, and
# health-checks them. Invocation is TWO-SURFACE: a sync endpoint's own `url`
# serves your HTTP service on arbitrary paths, whilst an async endpoint's jobs
# go through the shared gateway host (run/status/cancel/health) — never to the
# endpoint's url.
#
# Usage: nv serverless <verb> [flags]
#

_serverless_create() {
  local name product image app region
  name="$(nv::args_get name)"
  product="$(nv::args_get product)"
  image="$(nv::args_get image)"
  app="$(nv::args_get app)"
  region="$(nv::args_get region)"
  # The idempotency-by-name gate runs BEFORE the required-flag check, so a
  # re-run with just --name short-circuits instead of dying on usage.
  if nv::resource_existing serverless "$name"; then
    return 0
  fi
  [[ -n "$product" && -n "$image" && -n "$app" && -n "$region" ]] ||
    nv::usage "usage: nv serverless create --name <n> --product <id> --image <img> --app <name> --region <id> [--type sync|async] [--min 0] [--max 1] [--idle 300] [--policy queue|concurrency --policy-value N]"
  local etype
  etype="$(nv::args_get type sync)"
  # The create spec's enum is sync|async — `stream` never existed there.
  [[ "$etype" == "sync" || "$etype" == "async" ]] ||
    nv::usage "usage: nv serverless create --type expects sync|async (got '$etype')"
  local body='{}'
  nv::obj_set body type "$(nv::json_str "$etype")"
  nv::obj_set body name "$(nv::json_str "$name")"
  nv::obj_set body product_id "$(nv::json_str "$product")"
  nv::obj_set body image "$(nv::json_str "$image")"
  nv::obj_set body app_name "$(nv::json_str "$app")"
  nv::obj_set body region_id "$(nv::json_str "$region")"
  nv::obj_set_str body registry_auth_id "$(nv::args_get registry)"
  nv::obj_set_str body entrypoint "$(nv::args_get entrypoint)"
  nv::obj_set_str body command "$(nv::args_get command)"
  # worker_config is REQUIRED by the create spec (max_replicas required within
  # it), so the object is always sent; --max defaults to 1 when unset. Uint
  # reads are caught so a bad flag value exits 2 from THIS shell rather than
  # being swallowed inside the substitution.
  local wmin wmax wideal wconc wgpu wrootfs wtimeout wc
  wmin="$(nv::args_get_uint min)" || exit 2
  wmax="$(nv::args_get_uint max 1)" || exit 2
  wideal="$(nv::args_get_uint idle)" || exit 2
  wconc="$(nv::args_get_uint concurrent)" || exit 2
  wgpu="$(nv::args_get_uint gpu-count)" || exit 2
  wrootfs="$(nv::args_get_uint rootfs-gb)" || exit 2
  wtimeout="$(nv::args_get_uint request-timeout)" || exit 2
  wc="$(nv::json_worker_config "$wmin" "$wmax" "$wideal" "$wconc" "$wgpu" "$wrootfs" "$wtimeout")"
  nv::obj_set body worker_config "$wc"
  # policy: type defaults to queue; value defaults per the API when omitted.
  # Validate the type INLINE (never inside a command substitution) so a bad
  # value exits with usage code 2 from the caller's shell.
  local ptype pvalue
  ptype="$(nv::args_get policy)"
  pvalue="$(nv::args_get_uint policy-value)" || exit 2
  if [[ -n "$ptype" || -n "$pvalue" ]]; then
    case "$ptype" in
    queue | concurrency) ;;
    *) nv::usage "usage: nv serverless create --policy expects queue|concurrency (got '$ptype')" ;;
    esac
    nv::obj_set body policy "$(nv::json_policy "${ptype:-queue}" "$pvalue")"
  fi
  local envs ports volumes
  # The builders' usage errors must exit 2 from THIS shell, so each assignment
  # is caught here — an `exit 2` inside the substitution would be swallowed.
  envs="$(nv::envs_to_jsonarray "$(nv::args_get env)")" || exit 2
  [[ "$envs" == '[]' ]] || nv::obj_set body envs "$envs"
  ports="$(nv::ports_int_to_jsonarray "$(nv::args_get port)")" || exit 2
  [[ "$ports" == '[]' ]] || nv::obj_set body ports "$ports"
  volumes="$(nv::volume_mounts_to_jsonarray "$(nv::args_get volume)")" || exit 2
  [[ "$volumes" == '[]' ]] || nv::obj_set body volumes "$volumes"
  # health_check: either field may be given.
  local hc
  hc="$(nv::json_health_check "$(nv::args_get health-path)" "$(nv::args_get_uint health-port)")"
  [[ "$hc" == '{}' ]] || nv::obj_set body health_check "$hc"
  nv::resource_create serverless "$name" "$body" "$region"
}

# PATCH the endpoint with the flags that were set. The update route follows the
# REST convention (PATCH /endpoints/{id}); verify against the live API before
# relying on it — Novita's docs confirm create but not the update verb.
_serverless_update() {
  local id
  nv::require_pos id "usage: nv serverless update <id> [--name <n>] [--min N] [--max N] [--idle S]"
  local body='{}'
  nv::obj_set_str body name "$(nv::args_get name)"
  local wc
  wc="$(nv::json_worker_config \
    "$(nv::args_get_uint min)" \
    "$(nv::args_get_uint max)" \
    "$(nv::args_get_uint idle)" \
    "$(nv::args_get_uint concurrent)" \
    "" "" "")"
  [[ "$wc" == '{}' ]] || nv::obj_set body worker_config "$wc"
  [[ "$body" != '{}' ]] || nv::usage "nothing to update (use --name, --min, --max, --idle, --concurrent)"
  local res
  res="$(nv::http PATCH "/endpoints/$id" "$body")"
  nv::emit_json_or "$res" nv::ok "updated endpoint $id"
}

# Compose the async gateway's {endpoint_name} from a record: the SDK-documented
# `{endpoint_id}-{app_name}`, reducing to the bare id when no app_name applies.
# The record's display `name` never enters the job URL.
_serverless_endpoint_name() {
  local rec="$1" id="$2" app
  app="$(printf '%s' "$rec" | jq -r '.app_name // empty')"
  printf '%s' "${id}${app:+-$app}"
}

# Fetch the record and compose its async gateway name in one step — the
# status/cancel/health verbs (and async run) all need exactly this.
_serverless_endpoint_name_for() {
  local id="$1"
  _serverless_endpoint_name "$(nv::http GET "/endpoints/$id")" "$id"
}

# Async run body: wrap the payload as the documented {"input": …} job body. A
# payload that already carries an input key passes through unwrapped,
# mirroring the official SDK's run(); an empty payload wraps as {}. A
# non-JSON payload dies here — the gateway takes JSON only, and a silently
# empty body would be far harder to diagnose.
_serverless_async_body() {
  local input="$1"
  local payload="${input:-}"
  [[ -n "$payload" ]] || payload='{}'
  if printf '%s' "$payload" | jq -e 'type == "object" and has("input")' >/dev/null 2>&1; then
    printf '%s' "$payload"
    return 0
  fi
  jq -c -n --argjson input "$payload" '{input: $input}' 2>/dev/null ||
    nv::die "--input is not valid JSON: $payload"
}

# The two invocation surfaces, dispatched on the record's type:
#   sync  — POST the customer's HTTP service at {url}{path} (--path appends;
#           NO default path) through nv::http_url;
#   async — POST {"input": …} to the shared gateway /{endpoint_name}/run.
# --sync was removed with the /runsync route it targeted (the route appears in
# no current official doc): the flag dies pointing at the two surfaces.
_serverless_run() {
  local id input res rec
  nv::require_pos id "usage: nv serverless run <id> [--input <json>|@file] [--path <p>]"
  nv::require_id id "$id" "endpoint id"
  nv::args_has sync &&
    nv::usage "usage: nv serverless run <id> — --sync was removed (no /runsync route is documented); sync endpoints POST {url}{path} directly and async endpoints submit via the shared host — see 'nv doc serverless run'"
  input="$(nv::args_get input)"
  if [[ -n "$input" && "$input" == @* ]]; then
    input="$(<"${input#@}")" || nv::die "cannot read --input file: ${input#@}"
  fi
  rec="$(nv::http GET "/endpoints/$id")"
  if [[ "$(printf '%s' "$rec" | jq -r '.type // "sync"')" == "async" ]]; then
    [[ -z "$(nv::args_get path)" ]] ||
      nv::usage "usage: nv serverless run <id> — --path applies to sync endpoints only (async jobs go to the shared gateway)"
    local ename body
    ename="$(_serverless_endpoint_name "$rec" "$id")"
    # Serialize BEFORE the http_async substitution: a die inside $() would be
    # swallowed, so the builder's failure is caught out here instead.
    body="$(_serverless_async_body "$input")" || exit 1
    res="$(nv::http_async POST "/$ename/run" "$body")"
  else
    local url path
    url="$(printf '%s' "$rec" | jq -r '.url // empty')"
    [[ -n "$url" ]] || nv::die "endpoint $id returned no url — the record must carry the invoke URL"
    path="$(nv::args_get path)"
    res="$(nv::http_url POST "$url$path" "$input")"
  fi
  nv::emit_json_or "$res" printf '%s\n' "$res"
}

# Poll one async job. Output shape is only partially evidenced (status,
# output), so the response is passed through verbatim.
_serverless_status() {
  local id job ename res
  nv::require_pos id "usage: nv serverless status <id> <job_id>"
  nv::require_id id "$id" "endpoint id"
  nv::require_pos_at 1 job "usage: nv serverless status <id> <job_id>"
  nv::require_id job "$job" "job id"
  ename="$(_serverless_endpoint_name_for "$id")"
  res="$(nv::http_async GET "/$ename/status/$job")"
  nv::emit_json_or "$res" nv::json_pretty "$res"
}

# Cancel one async job: POST, no body, undocumented response — verbatim.
_serverless_cancel() {
  local id job ename res
  nv::require_pos id "usage: nv serverless cancel <id> <job_id>"
  nv::require_id id "$id" "endpoint id"
  nv::require_pos_at 1 job "usage: nv serverless cancel <id> <job_id>"
  nv::require_id job "$job" "job id"
  ename="$(_serverless_endpoint_name_for "$id")"
  res="$(nv::http_async POST "/$ename/cancel/$job")"
  nv::emit_json_or "$res" nv::json_pretty "$res"
}

# Async queue health: workers and jobs counters, verbatim.
_serverless_health() {
  local id ename res
  nv::require_pos id "usage: nv serverless health <id>"
  nv::require_id id "$id" "endpoint id"
  ename="$(_serverless_endpoint_name_for "$id")"
  res="$(nv::http_async GET "/$ename/health")"
  nv::emit_json_or "$res" nv::json_pretty "$res"
}

###
### :::: documentation (nv doc serverless) :::: ################################
###

# doc: list
# List your serverless endpoints as a table: id, name, url, region_id.
#
# Usage: nv serverless list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N      page size forwarded to the API (v2 cursor pagination)
#   --cursor <c>   opaque cursor of the next page; pairs with --limit
#   --jq <filter>  jq filter applied to the array
#   --json         print the raw API response
#
# API: GET /gpus/v2/endpoints?limit=N&cursor=<c>

# doc: get
# Show one endpoint's full record, including its invoke `url`.
#
# Usage: nv serverless get <id> [--jq <filter>] [--json]
#
# API: GET /gpus/v2/endpoints/{id}

# doc: create
# Create a serverless endpoint (BYO container).
#
# Usage: nv serverless create --name <n> --product <id> --image <img>
#                             --app <name> --region <id>
#                             [--type sync|async] [--min N] [--max N]
#                             [--idle S] [--concurrent N] [--gpu-count N]
#                             [--rootfs-gb N] [--request-timeout S]
#                             [--policy queue|concurrency] [--policy-value N]
#                             [--env K=V]… [--port <p>]…
#                             [--volume <storage-id>:<mount>]…
#                             [--registry <auth-id>] [--health-path <p>]
#                             [--health-port N] [--entrypoint <cmd>]
#                             [--command <args>] [--force]
#
# Notes:
#   --type is sync|async (default sync); --policy is queue|concurrency.
#   --port takes a bare integer 1-65535 — no ':protocol' suffix here.
#   The API requires a worker_config with an explicit max_replicas, so a bare
#   create sends --max 1; the scaling flags override.
#   Creation is idempotent by name; --force POSTs regardless. min 0 scales to
#   zero (cheap, cold starts); the policy arms map to Novita's queue-wait and
#   per-worker request-count scalers.
#   The new id is printed on stdout and the confirmation on stderr, so
#   `id=$(nv serverless create …)` captures just the id.
#
# Examples:
# # Cold-start-to-zero endpoint with a health check
# $ nv serverless create --name api --product <id> --image <img> \
#     --app my-app --region <id> --min 0 --max 1 --idle 300 \
#     --health-path /healthz --health-port 8080
#
# API: POST /gpus/v2/endpoints

# doc: update
# Patch an endpoint's scaling fields.
#
# Usage: nv serverless update <id> [--name <n>] [--min N] [--max N]
#                               [--idle S] [--concurrent N] [--json]
#
# Notes:
#   At least one flag is required; with none, the command exits with a usage
#   error rather than sending an empty PATCH. The PATCH route follows the REST
#   convention — Novita's docs confirm create but not update, so verify
#   against the live API before scripting this verb.
#
# API: PATCH /gpus/v2/endpoints/{id}  (route unverified)

# doc: delete
# Delete a serverless endpoint permanently.
#
# Usage: nv serverless delete <id>
#
# API: DELETE /gpus/v2/endpoints/{id}

# doc: run
# Invoke a job: sync endpoints POST the endpoint's url directly, async
# endpoints submit to the shared gateway.
#
# Usage: nv serverless run <id> [--input <json>|@file] [--path <p>]
#
# Arguments:
#   <id>             endpoint id — from `nv serverless list`
#
# Options:
#   --input <json>   request payload; inline JSON or @file
#   --path <p>       sync only: path appended to the endpoint's url
#                    (default: none — the url is POSTed bare)
#
# Notes:
#   Dispatched on the endpoint record's type. A sync endpoint's `url` serves
#   your HTTP service on arbitrary paths (e.g. --path /v1/chat/completions);
#   the payload is sent verbatim. An async endpoint submits {"input": …} to
#   the shared gateway (payloads already carrying an input key pass through),
#   which answers {id, status: PENDING}; poll with `nv serverless status`,
#   abort with `nv serverless cancel`. The sync surface can block on the
#   customer's service: invoke budget 300 s, override with NV_TIMEOUT_INVOKE.
#   --sync was removed: no /runsync route is documented.
#
# Examples:
# # Sync endpoint: chat completion against the customer path
# $ nv serverless run ep123 --path /v1/chat/completions --input '{"messages":[…]}'
# # Async endpoint: fire and forget, then poll
# $ nv serverless run ep123 --input '{"prompt":"hello"}'
# $ nv serverless status ep123 <job_id>
#
# API: GET /gpus/v2/endpoints/{id}, then POST {url}{path} (sync) or
#      POST https://async-public.serverless.novita.ai/v1/{endpoint_name}/run
#      (async)

# doc: status
# Poll one async job's status and output.
#
# Usage: nv serverless status <id> <job_id> [--json]
#
# Arguments:
#   <id>      endpoint id — from `nv serverless list`
#   <job_id>  job id — from `nv serverless run`
#
# Notes:
#   GETs the shared gateway (never the endpoint's url). Output is ≤ 4 MiB and
#   retained for 6 hours after completion.
#
# API: GET https://async-public.serverless.novita.ai/v1/{endpoint_name}/status/{job_id}

# doc: cancel
# Cancel one async job.
#
# Usage: nv serverless cancel <id> <job_id> [--json]
#
# Arguments:
#   <id>      endpoint id — from `nv serverless list`
#   <job_id>  job id — from `nv serverless run`
#
# API: POST https://async-public.serverless.novita.ai/v1/{endpoint_name}/cancel/{job_id}

# doc: health
# Show an async endpoint's queue health: worker and job counters.
#
# Usage: nv serverless health <id> [--json]
#
# Arguments:
#   <id>    endpoint id — from `nv serverless list`
#
# API: GET https://async-public.serverless.novita.ai/v1/{endpoint_name}/health

nv::cmd_serverless() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  # The record's region field is region_id — naming the column for the field
  # is what makes it render.
  list) nv::resource_list serverless id name url region_id ;;
  get) nv::resource_get serverless ;;
  create) _serverless_create ;;
  update) _serverless_update ;;
  delete) nv::resource_delete serverless ;;
  run) _serverless_run ;;
  status) _serverless_status ;;
  cancel) _serverless_cancel ;;
  health) _serverless_health ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv serverless <verb> [flags]
  create --name <n> --product <id> --image <img> --app <name> --region <id>
         [--type sync|async] [--min 0] [--max 1] [--idle 300]
         [--policy queue|concurrency --policy-value N] [--env K=V]...
         [--port N]... [--volume <id>:<path>]... [--health-path <p> --health-port N]
         (idempotent by name)
  list | get <id> | update <id> [--name|--min|--max|--idle|--concurrent] | delete <id>
  run <id> [--input <json>|@file] [--path <p>]   (sync: POSTs the endpoint's
                                                  url; async: shared gateway)
  status <id> <job_id> | cancel <id> <job_id> | health <id>   (async jobs)
EOF
    ;;
  *) nv::usage "unknown serverless verb: '$verb'" ;;
  esac
}
