#!/usr/bin/env bash
#
# Network storage: durable volumes mountable by instances and endpoints.
#
# Storage lives in one cluster (datacentre) and outlives every workload that
# mounts it. The v1 namespace splits the routes: list under
# /networkstorages/list (GET, pageNo/pageSize), create under
# /networkstorage/create (POST, camelCase body). The create response is a BARE
# JSON STRING holding the new storage id — nv::extract_id handles both shapes.
#
# Usage: nv volume <verb> [flags]
#

_volume_create() {
  local name size cluster
  name="$(nv::args_get name)"
  size="$(nv::args_get_uint size)"
  cluster="$(nv::args_get cluster)"
  [[ -n "$name" && -n "$size" && -n "$cluster" ]] ||
    nv::usage "usage: nv volume create --name <n> --size <gb> --cluster <id> (see: nv cluster list)"
  # v1 camelCase body; the response is a bare JSON string, which
  # nv::resource_create -> nv::extract_id unwraps directly.
  local body
  body="$(nv::json_obj clusterId "$(nv::json_str "$cluster")" \
    storageName "$(nv::json_str "$name")" \
    storageSize "$size")"
  nv::resource_create volume "$name" "$body" "$cluster, ${size}GB"
}

_volume_ls() {
  local body arr
  body="$(nv::http_v1 GET "/networkstorages/list$(nv::query_params \
    storageName "$(nv::args_get name)" \
    storageId "$(nv::args_get id)" \
    pageNo "$(nv::args_get page)" \
    pageSize "$(nv::args_get limit)")")"
  arr="$(nv::unwrap data "$body")"
  local jqf
  jqf="$(nv::args_get jq)"
  [[ -z "$jqf" ]] || arr="$(printf '%s' "$arr" | jq -c "$jqf")" || nv::die "invalid --jq filter: $jqf"
  nv::emit_json_or "$arr" nv::table "$arr" storageId storageName storageSize clusterName
}

###
### :::: documentation (nv doc volume) :::: ####################################
###

# doc: list
# List network storage as a table: storageId, storageName, storageSize, clusterName.
#
# Usage: nv volume list [--name <f>] [--id <f>] [--page N] [--limit N]
#                       [--jq <filter>] [--json]
#
# Options:
#   --name <f>     filter by storage name
#   --id <f>       filter by storage id
#   --page N       page number (v1 pageNo)
#   --limit N      page size (v1 pageSize)
#   --jq <filter>  jq filter applied to the array
#   --json         print the raw API response
#
# Notes:
#   The v1 namespace paginates with pageNo/pageSize — different from the v2
#   cursor scheme. Ids land in the storageId field, not `id`.
#
# API: GET /gpu-instance/openapi/v1/networkstorages/list

# doc: create
# Create network storage in a cluster.
#
# Usage: nv volume create --name <n> --size <gb> --cluster <id> [--force]
#
# Options:
#   --name <n>      storage name (required; enables idempotent re-runs)
#   --size <gb>     capacity in GB (required)
#   --cluster <id>  cluster id — see `nv cluster list` (required)
#   --force         create even when the name is taken
#
# Notes:
#   Creation is idempotent by name: where storage of that name already exists,
#   the CLI prints its id and skips the POST. --force sends the request
#   regardless.
#   The create response is a bare JSON string holding the new id (not an
#   object) — `id=$(nv volume create …)` captures it either way.
#   Storage is pinned to its cluster for life; workloads that mount it must
#   run there.
#
# Examples:
# # Create 100 GB of storage in cluster 5
# $ nv volume create --name shared-data --size 100 --cluster 5
#
# API: POST /gpu-instance/openapi/v1/networkstorage/create

nv::cmd_volume() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  list) _volume_ls ;;
  create) _volume_create ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv volume <verb> [flags]
  create --name <n> --size <gb> --cluster <id>   (idempotent by name; bare-string id response)
  list [--name <f>] [--id <f>] [--page N] [--limit N] [--json]
  (v1 namespace: camelCase bodies, pageNo/pageSize pagination)
EOF
    ;;
  *) nv::usage "unknown volume verb: '$verb'" ;;
  esac
}
