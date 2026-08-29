#!/usr/bin/env bash
#
# Templates: reusable instance configuration snapshots.
#
# A template bundles an image with its envs, ports and startup command so a
# workload can be re-created from one id. Create and update answer
# {"template_id": …} (not {"id": …}); the spec requires name, type and image
# on create, and `instance` is the only officially documented type value.
#
# Usage: nv template <verb> [flags]
#

_template_create() {
  local name etype image
  name="$(nv::args_get name)"
  etype="$(nv::args_get type)"
  image="$(nv::args_get image)"
  [[ -n "$name" && -n "$etype" && -n "$image" ]] ||
    nv::usage "usage: nv template create --name <n> --type <t> --image <img> [--env K=V] [--port p[:proto]]"
  local body='{}'
  nv::obj_set body name "$(nv::json_str "$name")"
  nv::obj_set body type "$(nv::json_str "$etype")"
  nv::obj_set body image "$(nv::json_str "$image")"
  local envs ports
  # The builders' usage errors must exit 2 from THIS shell, so each assignment
  # is caught here — an `exit 2` inside the substitution would be swallowed.
  envs="$(nv::envs_to_jsonarray "$(nv::args_get env)")" || exit 2
  [[ "$envs" == '[]' ]] || nv::obj_set body envs "$envs"
  # Template ports are {port, protocol} objects (instance shape), so bare
  # ports default to tcp and https is a usage error.
  ports="$(nv::ports_obj_to_jsonarray "$(nv::args_get port)")" || exit 2
  [[ "$ports" == '[]' ]] || nv::obj_set body ports "$ports"
  nv::resource_create template "$name" "$body"
}

# PUT /templates/{id} — the update spec takes the create key set with no key
# marked required, so only the set flags go on the wire.
_template_update() {
  local id
  nv::require_pos id "usage: nv template update <id> [--name <n>] [--type <t>] [--image <img>] [--registry <auth-id>] [--entrypoint <cmd>] [--command <args>] [--rootfs-gb N] [--env K=V] [--port p[:proto]]"
  nv::require_id id "$id" "template id"
  local body='{}'
  nv::obj_set_str body name "$(nv::args_get name)"
  nv::obj_set_str body type "$(nv::args_get type)"
  nv::obj_set_str body image "$(nv::args_get image)"
  nv::obj_set_str body registry_auth_id "$(nv::args_get registry)"
  nv::obj_set_str body entrypoint "$(nv::args_get entrypoint)"
  nv::obj_set_str body command "$(nv::args_get command)"
  local rootfs envs ports
  rootfs="$(nv::args_get_uint rootfs-gb)" || exit 2
  nv::obj_set body rootfs_size_gb "$rootfs"
  envs="$(nv::envs_to_jsonarray "$(nv::args_get env)")" || exit 2
  [[ "$envs" == '[]' ]] || nv::obj_set body envs "$envs"
  ports="$(nv::ports_obj_to_jsonarray "$(nv::args_get port)")" || exit 2
  [[ "$ports" == '[]' ]] || nv::obj_set body ports "$ports"
  [[ "$body" != '{}' ]] ||
    nv::usage "nothing to update (use --name, --type, --image, --registry, --entrypoint, --command, --rootfs-gb, --env, --port)"
  local res
  res="$(nv::http PUT "/templates/$id" "$body")"
  nv::emit_json_or "$res" nv::ok "updated template $id"
}

###
### :::: documentation (nv doc template) :::: ##################################
###

# doc: list
# List templates as a table: id, name.
#
# Usage: nv template list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N      page size forwarded to the API (v2 cursor pagination)
#   --cursor <c>   opaque cursor of the next page; pairs with --limit
#   --jq <filter>  jq filter applied to the array
#   --json         print the raw API response
#
# API: GET /gpus/v2/templates

# doc: create
# Create a template from an image.
#
# Usage: nv template create --name <n> --type <t> --image <img>
#                           [--env K=V] [--port p[:proto]] [--force]
#
# Options:
#   --name <n>        template name (required; enables idempotent re-runs)
#   --type <t>        template type (required; `instance` is the only value
#                     Novita's docs enumerate)
#   --image <img>     container image (required)
#   --env K=V         environment variable (repeatable)
#   --port p[:proto]  exposed port; proto tcp|http, default tcp (repeatable)
#   --force           create even when the name is taken
#
# Notes:
#   Creation is idempotent by name; --force POSTs regardless. The response
#   carries the new id under template_id, and the id is printed on stdout,
#   so `id=$(nv template create …)` captures just the id.
#
# API: POST /gpus/v2/templates

# doc: update
# Update a template (the update spec takes the create key set, none required).
#
# Usage: nv template update <id> [--name <n>] [--type <t>] [--image <img>]
#                               [--registry <auth-id>] [--entrypoint <cmd>]
#                               [--command <args>] [--rootfs-gb N]
#                               [--env K=V] [--port p[:proto]]
#
# Options:
#   --name <n>            template name
#   --type <t>            template type (`instance` is the documented value)
#   --image <img>         container image
#   --registry <auth-id>  container-registry auth id — see `nv registry list`
#   --entrypoint <cmd>    container entrypoint
#   --command <args>      container command/arguments
#   --rootfs-gb N         system disk size in GB
#   --env K=V             environment variable (repeatable)
#   --port p[:proto]      exposed port; proto tcp|http, default tcp (repeatable)
#
# Notes:
#   Only the set flags are sent; with none, the command exits with a usage
#   error rather than an empty PUT. The update answers the same
#   {"template_id": …} shape as create.
#
# API: PUT /gpus/v2/templates/{id}

# doc: delete
# Delete a template permanently.
#
# Usage: nv template delete <id>
#
# Arguments:
#   <id>    template id — from `nv template list`
#
# API: DELETE /gpus/v2/templates/{id}

nv::cmd_template() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  list) nv::resource_list template id name ;;
  create) _template_create ;;
  update) _template_update ;;
  delete) nv::resource_delete template ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv template <verb> [flags]
  create --name <n> --type <t> --image <img> [--env K=V]... [--port p[:proto]]...
         (idempotent by name)
  list [--json] [--jq <f>] [--limit N] [--cursor <c>]
  update <id> [--name|--type|--image|--registry|--entrypoint|--command|--rootfs-gb|--env|--port]
  delete <id>
EOF
    ;;
  *) nv::usage "unknown template verb: '$verb'" ;;
  esac
}
