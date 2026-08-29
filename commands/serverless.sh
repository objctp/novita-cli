#!/usr/bin/env bash
#
# Serverless GPU endpoints (BYO-container).
#
# An endpoint is an autoscaling pool of worker containers running your image:
# Novita schedules workers per the worker_config, scales on the policy, and
# health-checks them. Jobs are invoked against the endpoint's own `url` field
# (a customer-owned host), not a shared Novita data-plane host.
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
    nv::usage "usage: nv serverless create --name <n> --product <id> --image <img> --app <name> --region <id> [--min 0] [--max 1] [--idle 300] [--policy queue|request_count --policy-value N]"
  local etype
  etype="$(nv::args_get type sync)"
  [[ "$etype" == "sync" || "$etype" == "stream" ]] ||
    nv::usage "usage: invalid --type '$etype' (expected sync|stream)"
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
  # worker_config: every field optional; the API applies its own defaults.
  local wc
  wc="$(nv::json_worker_config \
    "$(nv::args_get_uint min)" \
    "$(nv::args_get_uint max)" \
    "$(nv::args_get_uint idle)" \
    "$(nv::args_get_uint concurrent)" \
    "$(nv::args_get_uint gpu-count)" \
    "$(nv::args_get_uint rootfs-gb)" \
    "$(nv::args_get_uint request-timeout)")"
  [[ "$wc" == '{}' ]] || nv::obj_set body worker_config "$wc"
  # policy: type defaults to queue; value defaults per the API when omitted.
  # Validate the type INLINE (never inside a command substitution) so a bad
  # value exits with usage code 2 from the caller's shell.
  local ptype pvalue
  ptype="$(nv::args_get policy)"
  pvalue="$(nv::args_get_uint policy-value)"
  if [[ -n "$ptype" || -n "$pvalue" ]]; then
    case "$ptype" in
    queue | request_count) ;;
    *) nv::usage "unknown policy type: '$ptype' (expected queue|request_count)" ;;
    esac
    nv::obj_set body policy "$(nv::json_policy "${ptype:-queue}" "$pvalue")"
  fi
  local envs ports volumes
  envs="$(nv::envs_to_jsonarray "$(nv::args_get env)")"
  [[ "$envs" == '[]' ]] || nv::obj_set body envs "$envs"
  ports="$(nv::ports_to_jsonarray "$(nv::args_get port)")"
  [[ "$ports" == '[]' ]] || nv::obj_set body ports "$ports"
  volumes="$(nv::volume_mounts_to_jsonarray "$(nv::args_get volume)")"
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

# Invoke a job on the endpoint's OWN url field (from the endpoint record), not a
# shared data-plane host. Default POSTs <url>/run (async); --sync posts
# <url>/runsync. The --input value (inline JSON, or @file) is sent as the body.
_serverless_run() {
  local id input url res
  nv::require_pos id "usage: nv serverless run <id> [--input <json>|@file] [--sync]"
  nv::require_id id "$id" "endpoint id"
  input="$(nv::args_get input)"
  if [[ -n "$input" && "$input" == @* ]]; then
    input="$(<"${input#@}")" || nv::die "cannot read --input file: ${input#@}"
  fi
  url="$(nv::http GET "/endpoints/$id" | jq -r '.url // empty')"
  [[ -n "$url" ]] || nv::die "endpoint $id returned no url — the record must carry the invoke URL"
  local path="/run"
  nv::args_has sync && path="/runsync"
  res="$(nv::http_url POST "$url$path" "$input")"
  nv::emit_json_or "$res" printf '%s\n' "$res"
}

###
### :::: documentation (nv doc serverless) :::: ################################
###

# doc: list
# List your serverless endpoints as a table: id, name, url, region.
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
#                             [--type sync|stream] [--min N] [--max N]
#                             [--idle S] [--concurrent N] [--gpu-count N]
#                             [--rootfs-gb N] [--request-timeout S]
#                             [--policy queue|request_count] [--policy-value N]
#                             [--env K=V]… [--port <p>[:<proto>]]…
#                             [--volume <storage-id>:<mount>]…
#                             [--registry <auth-id>] [--health-path <p>]
#                             [--health-port N] [--entrypoint <cmd>]
#                             [--command <args>] [--force]
#
# Notes:
#   Creation is idempotent by name; --force POSTs regardless. min 0 scales to
#   zero (cheap, cold starts); the policy arms map to Novita's queue-delay and
#   request-count scalers.
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
# Invoke a job on the endpoint's own URL.
#
# Usage: nv serverless run <id> [--input <json>|@file] [--sync]
#
# Arguments:
#   <id>             endpoint id — from `nv serverless list`
#
# Options:
#   --input <json>   request body; inline JSON or @file (default: empty)
#   --sync           POST <url>/runsync instead of <url>/run (blocks on the job)
#
# Notes:
#   The endpoint record carries its own `url` field; the job goes there, not
#   to a shared Novita host. Without --sync the call returns as soon as the
#   job is accepted. The invoke budget is 300 s; override with NV_TIMEOUT_INVOKE.
#
# Examples:
# # Fire and forget
# $ nv serverless run ep123 --input '{"prompt":"hello"}'
# # Block until the job completes
# $ nv serverless run ep123 --sync --input @job.json
#
# API: GET /gpus/v2/endpoints/{id}, then POST <url>/run|/runsync

nv::cmd_serverless() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  list) nv::resource_list serverless id name url region ;;
  get) nv::resource_get serverless ;;
  create) _serverless_create ;;
  update) _serverless_update ;;
  delete) nv::resource_delete serverless ;;
  run) _serverless_run ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv serverless <verb> [flags]
  create --name <n> --product <id> --image <img> --app <name> --region <id>
         [--type sync|stream] [--min 0] [--max 1] [--idle 300]
         [--policy queue|request_count --policy-value N] [--env K=V]...
         [--port p[:proto]]... [--volume <id>:<path>]... [--health-path <p> --health-port N]
         (idempotent by name)
  list | get <id> | update <id> [--name|--min|--max|--idle|--concurrent] | delete <id>
  run <id> [--input <json>|@file] [--sync]   (POSTs the endpoint's own url)
EOF
    ;;
  *) nv::usage "unknown serverless verb: '$verb'" ;;
  esac
}
