#!/usr/bin/env bash
#
# Templates: reusable pod/serverless configuration snapshots.
#
# Usage: nv template <verb> [flags]
#

# POST /gpus/v2/templates — the list path is confirmed; the create route is the
# REST-convention guess (Novita's docs confirm list but not create), so this
# verb is documented as unverified.
_template_create() {
  local name image
  name="$(nv::args_get name)"
  image="$(nv::args_get image)"
  [[ -n "$name" && -n "$image" ]] || nv::usage "usage: nv template create --name <n> --image <img> [--env K=V] [--port p[:proto]]"
  local body='{}'
  nv::obj_set body name "$(nv::json_str "$name")"
  nv::obj_set body image "$(nv::json_str "$image")"
  local envs ports
  envs="$(nv::envs_to_jsonarray "$(nv::args_get env)")"
  [[ "$envs" == '[]' ]] || nv::obj_set body envs "$envs"
  ports="$(nv::ports_to_jsonarray "$(nv::args_get port)")"
  [[ "$ports" == '[]' ]] || nv::obj_set body ports "$ports"
  nv::resource_create template "$name" "$body"
}

###
### :::: documentation (nv doc template) :::: ##################################
###

# doc: list
# List templates as a table: id, name.
#
# Usage: nv template list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# API: GET /gpus/v2/templates

# doc: create
# Create a template from an image.
#
# Usage: nv template create --name <n> --image <img> [--env K=V] [--port p[:proto]]
#
# Notes:
#   The list path is confirmed, but Novita's docs do not confirm a create
#   route; this verb POSTs /gpus/v2/templates per REST convention and may need
#   adjusting once the route is verified.
#
# API: POST /gpus/v2/templates  (route unverified)

nv::cmd_template() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  list) nv::resource_list template id name ;;
  create) _template_create ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv template <verb> [flags]
  list [--json] [--jq <f>] [--limit N] [--cursor <c>]
  create --name <n> --image <img> [--env K=V]... [--port p[:proto]]...
         (create route unverified — list is confirmed)
EOF
    ;;
  *) nv::usage "unknown template verb: '$verb'" ;;
  esac
}
