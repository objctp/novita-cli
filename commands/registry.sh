#!/usr/bin/env bash
#
# Container-registry auths: credentials Novita uses to pull private images.
#
# Referenced as registry_auth_id in instance/endpoint create bodies
# (`nv pod create --registry <id>`). The v1 namespace confirms only the list
# route — auths are normally created in the Novita console, so this command is
# read-only.
#
# Usage: nv registry <verb> [flags]
###

_registry_list() {
  local body arr
  body="$(nv::http_v1 GET "/repository/auths$(nv::query_params \
    pageNo "$(nv::args_get page)" pageSize "$(nv::args_get limit)")")"
  arr="$(nv::unwrap data "$body")"
  local jqf
  jqf="$(nv::args_get jq)"
  [[ -z "$jqf" ]] || arr="$(printf '%s' "$arr" | jq -c "$jqf")" || nv::die "invalid --jq filter: $jqf"
  # Record shape is not fully documented; project defensively so a table still
  # renders if fields land under nested or alternative keys.
  nv::emit_json_or "$arr" nv::table "$arr" --reshape \
    'map({id: (.id // .authId // ""), name: (.name // .username // ""), registry: (.registryUrl // .url // "")})' \
    id name registry
}

###
### :::: documentation (nv doc registry) :::: ##################################
###

# doc: list
# List container-registry auths.
#
# Usage: nv registry list [--json] [--jq <filter>] [--page N] [--limit N]
#
# Notes:
#   Each auth's id feeds `nv pod create --registry <id>` /
#   `nv serverless create --registry <id>`. The v1 namespace confirms only the
#   list route; create and delete happen in the Novita console. The record
#   shape is not fully documented, so prefer --json when scripting.
#
# API: GET /gpu-instance/openapi/v1/repository/auths

nv::cmd_registry() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  list) _registry_list ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv registry <verb> [flags]
  list [--json] [--jq <f>] [--page N] [--limit N]
       (read-only — auths are created in the console; ids feed --registry)
EOF
    ;;
  *) nv::usage "unknown registry verb: '$verb'" ;;
  esac
}
