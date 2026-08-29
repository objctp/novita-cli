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
    nv::usage "usage: nv pod create [--name <n>] --product <id> --image <img> [--gpu-count N] [--region <id,id>] [--env K=V] [--port N] [--volume <id>:<path>]"
  local body='{}'
  # Optional strings: nv::obj_set_str skips them when unset (an unset --name
  # must not become {"name":""} on the wire).
  nv::obj_set_str body name "$name"
  nv::obj_set body product_id "$(nv::json_str "$product")"
  nv::obj_set body image "$(nv::json_str "$image")"
  # resource{rootfs_size_gb, gpu_num} — the nested v2 shape; both default on the
  # API side, so unset flags are skipped.
  local resource='{}'
  nv::obj_set resource rootfs_size_gb "$(nv::args_get_uint rootfs-gb)"
  nv::obj_set resource gpu_num "$(nv::args_get_uint gpu-count)"
  [[ "$resource" == '{}' ]] || nv::obj_set body resource "$resource"
  nv::obj_set_str body registry_auth_id "$(nv::args_get registry)"
  nv::obj_set_str body entrypoint "$(nv::args_get entrypoint)"
  nv::obj_set_str body command "$(nv::args_get command)"
  local envs ports volumes regions
  envs="$(nv::envs_to_jsonarray "$(nv::args_get env)")"
  [[ "$envs" == '[]' ]] || nv::obj_set body envs "$envs"
  ports="$(nv::ports_to_jsonarray "$(nv::args_get port)")"
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

# POST /instances/{id}/start and /stop. Both are idempotent-ish state
# transitions; the response body is discarded.
_pod_lifecycle() {
  local verb="$1" id
  nv::require_pos id "usage: nv pod $verb <id>"
  nv::require_id id "$id" "instance id"
  nv::http POST "/instances/$id/$verb" >/dev/null
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
#                      [--gpu-count N] [--rootfs-gb N] [--region <id,…>]
#                      [--env K=V]… [--port <p>[:<proto>]]…
#                      [--volume <storage-id>:<mount>]…
#                      [--registry <auth-id>] [--entrypoint <cmd>]
#                      [--command <args>] [--jupyter [--jupyter-port N]] [--force]
#
# Options:
#   --name <n>            instance name (enables idempotent re-runs)
#   --product <id>        GPU product id — see `nv catalog gpu` (required)
#   --image <img>         container image (required)
#   --gpu-count N         number of GPUs (default: product default)
#   --rootfs-gb N         system disk size in GB (default: 20)
#   --region <id,…>       candidate regions, csv or repeated
#   --env K=V             environment variable (repeatable)
#   --port p[:proto]      exposed port; proto tcp|http|https (repeatable)
#   --volume id:path      network-storage mount (repeatable; default /data)
#   --registry <auth-id>  container-registry auth id — see `nv registry list`
#   --entrypoint <cmd>    container entrypoint
#   --command <args>      container command/arguments
#   --jupyter             enable the Jupyter tool (port 8888, http)
#   --force               create even when the name is taken
#
# Notes:
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
# API: POST /gpus/v2/instances/{id}/start

# doc: stop
# Stop a running instance (keeps the rootfs; stops GPU billing).
#
# Usage: nv pod stop <id>
#
# API: POST /gpus/v2/instances/{id}/stop

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
  list) nv::resource_list pod id name status region ;;
  get) nv::resource_get pod ;;
  create) _pod_create ;;
  start) _pod_lifecycle start ;;
  stop) _pod_lifecycle stop ;;
  delete) nv::resource_delete pod ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv pod <verb> [flags]
  create [--name <n>] --product <id> --image <img> [--gpu-count N] [--rootfs-gb N]
         [--region <id,id>] [--env K=V]... [--port p[:proto]]...
         [--volume <id>:<path>]... [--registry <auth-id>] [--jupyter] [--force]
         (idempotent by name)
  list | get <id> | delete <id>
  start <id> | stop <id>
EOF
    ;;
  *) nv::usage "unknown pod verb: '$verb'" ;;
  esac
}
