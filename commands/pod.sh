#!/usr/bin/env bash
#
# GPU instance lifecycle ("pods").
#
# An instance is a rented GPU container: pick a product (GPU shape), an image,
# and a region; Novita schedules it and bills while it runs. Start/stop keeps
# the instance (and its rootfs) around without paying for the GPU.
#
# Usage: nv pod <verb> [flags]
#

_pod_create() {
  local name product image
  name="$(nv::args_get name)"
  product="$(nv::args_get product)"
  image="$(nv::args_get image)"
  [[ -n "$product" && -n "$image" ]] ||
    nv::usage "usage: nv pod create [--name <n>] --product <id> --image <img> [--billing-mode postpaid|prepaid|spot] [--gpu-count N] [--rootfs-gb N] [--region <id,id>] [--env K=V] [--port N] [--volume <id>:<path>]"
  local body='{}'
  # Optional strings: nv::obj_set_str skips them when unset (an unset --name
  # must not become {"name":""} on the wire).
  nv::obj_set_str body name "$name"
  nv::obj_set body product_id "$(nv::json_str "$product")"
  nv::obj_set body image "$(nv::json_str "$image")"
  # billing.mode is required by the create spec; postpaid is the pay-as-you-go
  # default. Validated INLINE (never inside a command substitution) so a bad
  # value exits with usage code 2 from the caller's shell.
  local bmode
  bmode="$(nv::args_get billing-mode postpaid)"
  case "$bmode" in
  postpaid | prepaid | spot) ;;
  *) nv::usage "usage: nv pod create --billing-mode expects postpaid|prepaid|spot (got '$bmode')" ;;
  esac
  nv::obj_set body billing "$(nv::json_obj mode "$(nv::json_str "$bmode")")"
  # resource{rootfs_size_gb, gpu_num} — the nested v2 shape, with BOTH keys
  # required by the create spec, so the object is always sent; documented
  # example values (1 GPU, 20 GB rootfs) stand in when flags are unset. The
  # uint reads are caught so a bad flag value exits 2 from THIS shell rather
  # than being swallowed inside the substitution.
  local rootfs_gb gpu_num
  rootfs_gb="$(nv::args_get_uint rootfs-gb 20)" || exit 2
  gpu_num="$(nv::args_get_uint gpu-count 1)" || exit 2
  local resource='{}'
  nv::obj_set resource rootfs_size_gb "$rootfs_gb"
  nv::obj_set resource gpu_num "$gpu_num"
  nv::obj_set body resource "$resource"
  nv::obj_set_str body registry_auth_id "$(nv::args_get registry)"
  nv::obj_set_str body entrypoint "$(nv::args_get entrypoint)"
  nv::obj_set_str body command "$(nv::args_get command)"
  local envs ports volumes regions
  envs="$(nv::envs_to_jsonarray "$(nv::args_get env)")"
  [[ "$envs" == '[]' ]] || nv::obj_set body envs "$envs"
  # The builder's usage errors must exit 2 from THIS shell, so the assignment
  # is caught here — an `exit 2` inside the substitution would be swallowed.
  ports="$(nv::ports_obj_to_jsonarray "$(nv::args_get port)")" || exit 2
  [[ "$ports" == '[]' ]] || nv::obj_set body ports "$ports"
  volumes="$(nv::volume_mounts_to_jsonarray "$(nv::args_get volume)")"
  [[ "$volumes" == '[]' ]] || nv::obj_set body volumes "$volumes"
  regions="$(nv::regions_to_jsonarray "$(nv::args_get region)")"
  [[ "$regions" == '[]' ]] || nv::obj_set body candidate_regions "$regions"
  # --jupyter embeds the tools.jupyter block (port defaults to 8888).
  if nv::args_has jupyter; then
    nv::obj_set body tools "$(nv::json_obj jupyter "$(nv::json_obj enabled true \
      port "$(nv::args_get_uint jupyter-port 8888)" protocol "$(nv::json_str http)")")"
  fi
  nv::resource_create pod "$name" "$body" "$product"
}

# PUT /instances/{id}/start and /stop — the v2 specs give both lifecycle routes
# no request body; the response body is discarded.
_pod_lifecycle() {
  local verb="$1" id
  nv::require_pos id "usage: nv pod $verb <id>"
  nv::require_id id "$id" "instance id"
  nv::http PUT "/instances/$id/$verb" >/dev/null
  nv::ok "${verb}ed instance $id"
}

###
### :::: documentation (nv doc pod) :::: #######################################
###

# doc: list
# List your GPU instances as a table: id, name, status, region.
#
# Usage: nv pod list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N      page size forwarded to the API (v2 cursor pagination)
#   --cursor <c>   opaque cursor of the next page; pairs with --limit
#   --jq <filter>  jq filter applied to the array
#   --json         print the raw API response
#
# Notes:
#   The status column renders the nested status.status state — `error` and
#   `message` stay on the record for --json/--jq, keeping the table one line
#   per pod.
#   Pages are fetched server-side (v2 cursor pagination). When more pages
#   exist, the next cursor is printed to stderr, leaving stdout clean for
#   scripts; pass it back with --cursor.
#
# API: GET /gpus/v2/instances?limit=N&cursor=<c>

# doc: get
# Show one instance's full record.
#
# Usage: nv pod get <id> [--jq <filter>] [--json]
#
# Arguments:
#   <id>           instance id — from `nv pod list`
#
# API: GET /gpus/v2/instances/{id}

# doc: create
# Create a GPU instance.
#
# Usage: nv pod create [--name <n>] --product <id> --image <img>
#                      [--billing-mode postpaid|prepaid|spot] [--gpu-count N]
#                      [--rootfs-gb N] [--region <id,…>]
#                      [--env K=V]… [--port <p>[:<tcp|http>]]…
#                      [--volume <storage-id>:<mount>]…
#                      [--registry <auth-id>] [--entrypoint <cmd>]
#                      [--command <args>] [--jupyter [--jupyter-port N]] [--force]
#
# Options:
#   --name <n>            instance name (enables idempotent re-runs)
#   --product <id>        GPU product id — see `nv catalog gpu` (required)
#   --image <img>         container image (required)
#   --billing-mode <m>    postpaid | prepaid | spot (default: postpaid)
#   --gpu-count N         number of GPUs (default: 1)
#   --rootfs-gb N         system disk size in GB (default: 20)
#   --region <id,…>       candidate regions, csv or repeated
#   --env K=V             environment variable (repeatable)
#   --port p[:proto]      exposed port; proto tcp|http, default tcp (repeatable)
#   --volume id:path      network-storage mount (repeatable; default /data)
#   --registry <auth-id>  container-registry auth id — see `nv registry list`
#   --entrypoint <cmd>    container entrypoint
#   --command <args>      container command/arguments
#   --jupyter             enable the Jupyter tool (port 8888, http)
#   --force               create even when the name is taken
#
# Notes:
#   The API requires a billing mode and an explicit resource block, so bare
#   creates send billing.mode=postpaid, 1 GPU and a 20 GB rootfs; the flags
#   above override.
#   Creation is idempotent by name: where an instance of that name already
#   exists, the CLI prints its id and skips the POST. --force sends the
#   request regardless.
#   The new id is printed on stdout and the confirmation on stderr, so
#   `id=$(nv pod create …)` captures just the id.
#
# Examples:
# # Create a single-GPU dev box with Jupyter
# $ nv pod create --name dev --product <id> \
#     --image docker.io/library/ubuntu:22.04 --jupyter
#
# API: POST /gpus/v2/instances

# doc: start
# Start a stopped instance.
#
# Usage: nv pod start <id>
#
# API: PUT /gpus/v2/instances/{id}/start

# doc: stop
# Stop a running instance (keeps the rootfs; stops GPU billing).
#
# Usage: nv pod stop <id>
#
# API: PUT /gpus/v2/instances/{id}/stop

# doc: delete
# Delete an instance permanently (rootfs included).
#
# Usage: nv pod delete <id>
#
# API: DELETE /gpus/v2/instances/{id}

nv::cmd_pod() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  # The record's status is a nested object {status, error, message}; the table
  # reshapes to the inner status so a pod stays one line (error/message remain
  # on the record for --json/--jq).
  list) nv::resource_list pod --reshape \
    'map(. + {status: ((.status | if type == "object" then .status else . end) // "")})' \
    id name status region ;;
  get) nv::resource_get pod ;;
  create) _pod_create ;;
  start) _pod_lifecycle start ;;
  stop) _pod_lifecycle stop ;;
  delete) nv::resource_delete pod ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv pod <verb> [flags]
  create [--name <n>] --product <id> --image <img> [--billing-mode m] [--gpu-count N]
         [--rootfs-gb N] [--region <id,id>] [--env K=V]... [--port p[:tcp|http]]...
         [--volume <id>:<path>]... [--registry <auth-id>] [--jupyter] [--force]
         (idempotent by name)
  list | get <id> | delete <id>
  start <id> | stop <id>
EOF
    ;;
  *) nv::usage "unknown pod verb: '$verb'" ;;
  esac
}
