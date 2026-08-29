#!/usr/bin/env bash
# Resource descriptor + shared verbs. A resource is a Novita noun exposed as
# `nv <resource>`: the descriptor maps it to its REST path, its API namespace
# (v2 | v1), and a human label; nv::resource_list/get/delete/create and
# nv::resource_id consume it. Bespoke verbs (run, start, stop…) stay in
# commands/<resource>.sh.
#
# Novita's namespace split is by RESOURCE, not by a single "plane": most nouns
# live under v2 (/gpus/v2, snake_case), but clusters / network storage /
# repository auths live under v1 (/gpu-instance/openapi/v1, camelCase). The
# descriptor carries `ns` so the shared verbs route through nv::res_http.
#
# Most resources share ONE path for list and create, but the v1 storage API
# splits them (list /networkstorages/list vs create /networkstorage/create), so
# the descriptor carries an optional create-path override.
#
# Every Novita list unwraps under the same key, "data" (v2 envelopes add
# next_cursor/has_more; the v1 storage list adds total) — no per-resource key.
#
# Locals are res_-prefixed: these functions call back into nv::res_http, which
# tests override with doubles that read their own outer variables — an
# unprefixed `local body` would shadow them (same convention as _mktemp's
# mktemp_out).
[[ -n "${_NV_RESOURCE:-}" ]] && return 0
_NV_RESOURCE=1

# Set NV_RES_PATH / NV_RES_NS / NV_RES_LABEL (and optionally NV_RES_CREATE_PATH)
# for $1, or nv::usage on an unknown resource. Internal seam — only this module's
# verbs read the globals.
_resource_meta() {
  case "$1" in
  pod)
    NV_RES_PATH=/instances
    NV_RES_NS=v2
    NV_RES_LABEL=pod
    ;;
  serverless)
    NV_RES_PATH=/endpoints
    NV_RES_NS=v2
    NV_RES_LABEL=endpoint
    ;;
  template)
    NV_RES_PATH=/templates
    NV_RES_NS=v2
    NV_RES_LABEL=template
    ;;
  cluster)
    NV_RES_PATH=/clusters
    NV_RES_NS=v1
    NV_RES_LABEL=cluster
    ;;
  volume)
    NV_RES_PATH=/networkstorages/list
    NV_RES_CREATE_PATH=/networkstorage/create
    NV_RES_NS=v1
    NV_RES_LABEL=volume
    ;;
  registry)
    NV_RES_PATH=/repository/auths
    NV_RES_NS=v1
    NV_RES_LABEL="registry auth"
    ;;
  *) nv::usage "unknown resource: '$1'" ;;
  esac
}

# Create path for a resource: the descriptor override when present (v1 storage),
# else the list path. Caller must have run _resource_meta first.
_res_create_path() {
  printf '%s' "${NV_RES_CREATE_PATH:-$NV_RES_PATH}"
}

# List a resource: GET (with the namespace's pagination params), unwrap `data`,
# surface the v2 next-cursor hint, then --json or a table. Remaining args go to
# nv::table: column names, plus its options (e.g. --reshape '<jq>') — --json
# prints the unwrapped array untouched, so reshaping never reaches scripts.
# $1 resource; remaining args are the table's columns (and options).
nv::resource_list() {
  local res_resource="$1"
  shift
  _resource_meta "$res_resource"
  local res_body res_arr res_raw
  res_raw="$(nv::res_http GET "$NV_RES_PATH$(nv::page_query "$NV_RES_NS")")"
  # Keep the raw envelope for the next-cursor hint before unwrapping.
  res_body="$res_raw"
  res_arr="$(nv::unwrap data "$res_raw")"
  nv::more_hint "$res_body"
  local jqf
  jqf="$(nv::args_get jq)"
  [[ -z "$jqf" ]] || res_arr="$(printf '%s' "$res_arr" | jq -c "$jqf")" || nv::die "invalid --jq filter: $jqf"
  nv::emit_json_or "$res_arr" nv::table "$res_arr" "$@"
}

# Get one record by the positional id: --json raw or pretty-printed JSON.
# Arguments:
#   $1 - resource: resource name (pod, volume, ...)
nv::resource_get() {
  local res_resource="$1" res_id res_body
  _resource_meta "$res_resource"
  nv::require_pos res_id "usage: nv $res_resource get <id>"
  nv::require_id res_id "$res_id" "$NV_RES_LABEL id"
  res_body="$(nv::res_http GET "$NV_RES_PATH/$res_id")"
  local jqf
  jqf="$(nv::args_get jq)"
  [[ -z "$jqf" ]] || res_body="$(printf '%s' "$res_body" | jq -c "$jqf")" || nv::die "invalid --jq filter: $jqf"
  nv::emit_json_or "$res_body" nv::json_pretty "$res_body"
}

# Delete a record by the positional id. The v1 storage writes are NOT REST
# DELETEs — they POST /networkstorage/{delete,update} with camelCase bodies on
# the singular path — so volume keeps bespoke verbs in commands/volume.sh and
# never dispatches here.
# Arguments:
#   $1 - resource: resource name (pod, serverless, ...)
nv::resource_delete() {
  local res_resource="$1" res_id
  _resource_meta "$res_resource"
  nv::require_pos res_id "usage: nv $res_resource delete <id>"
  nv::require_id res_id "$res_id" "$NV_RES_LABEL id"
  nv::res_http DELETE "$NV_RES_PATH/$res_id" >/dev/null
  nv::ok "deleted $NV_RES_LABEL $res_id"
}

# Idempotency-by-name gate for create paths: when $2 names an existing record
# (and --force was not given), confirm on stderr, print the id on stdout, and
# return 0; otherwise return 1 so the caller proceeds to build and POST a body.
# nv::resource_create gates on this, and create verbs that die on missing
# required flags before reaching it (serverless) call it first so the gate
# stays reachable.
# Arguments:
#   $1 - resource: resource name (pod, volume, serverless, ...)
#   $2 - name: optional; empty always returns 1
# Returns:
#   0 - existing record found; id printed, caller must not POST
#   1 - no name, --force given, or no match; caller proceeds
nv::resource_existing() {
  local res_resource="$1" res_name="${2:-}"
  [[ -n "$res_name" ]] || return 1
  nv::args_has force && return 1
  _resource_meta "$res_resource"
  local res_existing
  res_existing="$(nv::resource_id "$res_resource" "$res_name")"
  [[ -n "$res_existing" ]] || return 1
  nv::ok "$NV_RES_LABEL '$res_name' exists: $res_existing"
  printf '%s\n' "$res_existing"
}

# Create a record: POST the prepared body to the resource's create path,
# extract the new id (object .id or bare string — see nv::extract_id), confirm
# on stderr, print the id on stdout.
# Arguments:
#   $1 - resource: resource name (pod, volume, serverless, ...)
#   $2 - name: optional; non-empty makes the create idempotent by name
#   $3 - body: JSON request body
#   $4 - detail: optional text appended to the success message
# Returns:
#   0 - created (or existing id printed when idempotent by name)
#   1 - create failed (dies)
# With a non-empty $2 and no --force, nv::resource_existing prints the existing
# record's id instead of POSTing; an empty $2 always POSTs (pod).
nv::resource_create() {
  local res_resource="$1" res_name="$2" res_body="$3" res_detail="${4:-}"
  _resource_meta "$res_resource"
  if nv::resource_existing "$res_resource" "$res_name"; then
    return 0
  fi
  local res_res res_newid
  res_res="$(nv::res_http POST "$(_res_create_path)" "$res_body")"
  nv::extract_id res_newid "$res_res" "$NV_RES_LABEL"
  nv::ok "created $NV_RES_LABEL${res_name:+ '$res_name'}: $res_newid${res_detail:+ ($res_detail)}"
  printf '%s\n' "$res_newid"
}

# Resolve a resource name to its id via list + filter. The id field name varies
# by namespace/record shape (v2 records carry `id`; v1 storage records carry
# `storageId`), so $3 names the id field and $4 the name field; both default to
# "id"/"name". Prints the id or nothing when no record matches.
nv::resource_id() {
  local res_resource="$1" res_name="$2" idf="${3:-id}" namef="${4:-name}"
  _resource_meta "$res_resource"
  nv::res_http GET "$NV_RES_PATH$(nv::page_query "$NV_RES_NS")" |
    nv::unwrap data |
    jq -r --arg n "$res_name" --arg idf "$idf" --arg namef "$namef" '
        (if type == "array" then . else [] end)
        | map(select(.[$namef] == $n)) | .[0][$idf] // empty'
}
