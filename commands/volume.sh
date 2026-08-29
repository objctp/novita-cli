#!/usr/bin/env bash
#
# Network storage: durable volumes mountable by instances and endpoints.
#
# Storage lives in one cluster (datacentre) and outlives every workload that
# mounts it. The v1 namespace splits the routes: list under
# /networkstorages/list (GET, pageNo/pageSize), and the writes under
# /networkstorage/{create,update,delete} (POST, camelCase bodies). The create
# response is a BARE JSON STRING holding the new storage id — nv::extract_id
# handles both shapes.
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

# v1 splits the write routes (create/update/delete under /networkstorage/*),
# so these verbs POST a camelCase body instead of a REST DELETE/PUT on the
# list path — nv::resource_delete cannot express them.
_volume_delete() {
  local id body
  nv::require_pos id "usage: nv volume delete <id>"
  nv::require_id id "$id" "storage id"
  body="$(nv::json_obj storageId "$(nv::json_str "$id")")"
  nv::http_v1 POST /networkstorage/delete "$body" >/dev/null
  nv::ok "deleted volume $id"
}

_volume_update() {
  local id name size body
  nv::require_pos id "usage: nv volume update <id> [--name <n>] [--size <gb>]"
  nv::require_id id "$id" "storage id"
  name="$(nv::args_get name)"
  # The uint read is caught so a bad flag value exits 2 from THIS shell rather
  # than being swallowed inside the substitution.
  size="$(nv::args_get_uint size)" || exit 2
  [[ -n "$name" || -n "$size" ]] || nv::usage "nothing to update (use --name, --size)"
  body="$(nv::json_obj storageId "$(nv::json_str "$id")")"
  nv::obj_set_str body storageName "$name"
  nv::obj_set body storageSize "$size"
  nv::http_v1 POST /networkstorage/update "$body" >/dev/null
  nv::ok "updated volume $id"
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

# doc: delete
# Delete network storage permanently.
#
# Usage: nv volume delete <id>
#
# Arguments:
#   <id>    storage id — from `nv volume list`
#
# API: POST /gpu-instance/openapi/v1/networkstorage/delete

# doc: update
# Rename or resize network storage.
#
# Usage: nv volume update <id> [--name <n>] [--size <gb>]
#
# Options:
#   --name <n>    new storage name
#   --size <gb>   new capacity in GB
#
# Notes:
#   At least one flag is required; with none, the command exits with a usage
#   error rather than sending an empty update. Resizing is subject to the
#   API's rules — a shrink may be rejected server-side.
#
# API: POST /gpu-instance/openapi/v1/networkstorage/update

nv::cmd_volume() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  list) _volume_ls ;;
  create) _volume_create ;;
  delete) _volume_delete ;;
  update) _volume_update ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv volume <verb> [flags]
  create --name <n> --size <gb> --cluster <id>   (idempotent by name; bare-string id response)
  list [--name <f>] [--id <f>] [--page N] [--limit N] [--json]
  delete <id>
  update <id> [--name <n>] [--size <gb>]
  (v1 namespace: camelCase bodies, pageNo/pageSize pagination)
EOF
    ;;
  *) nv::usage "unknown volume verb: '$verb'" ;;
  esac
}
