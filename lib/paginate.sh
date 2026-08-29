#!/usr/bin/env bash
# Pagination for list verbs. Novita's two namespaces paginate differently, so
# this module carries BOTH shapes behind two small helpers, plus a client-side
# slicer for raw `nv api` output:
#
#   v2 — server-side cursor pagination: the request forwards `limit` (page size)
#        and `cursor` (opaque string, 0-1024 chars) as query params; the envelope
#        answers {data, next_cursor, has_more, total}. nv::page_query builds the
#        request params; nv::more_hint surfaces the next cursor to stderr.
#   v1 — pageNo/pageSize pagination: nv::page_query maps --page/--limit onto
#        pageNo/pageSize query params (the v1 network-storage list shape).
#
# Reads --limit / --cursor / --page from NV_ARGS, set by the calling verb's
# args_parse. Deliberately a standalone module, not folded into the thin nv::http
# facade, so the depth (param building + next-cursor hint) lives in one place
# shared by nv::resource_list and nv api.
[[ -n "${_NV_PAGINATE:-}" ]] && return 0
_NV_PAGINATE=1

# Build the pagination query params for a list request, per namespace.
# Arguments:
#   $1 - ns: API namespace (v2 | v1)
# Prints:
#   "" (no flags set) or "?k=v&…" ready to splice onto the path.
#   v2: --limit -> limit, --cursor -> cursor (opaque string; NOT uint-checked)
#   v1: --page -> pageNo, --limit -> pageSize
# v1 list verbs that take no pagination simply pass an empty ns — call
# nv::page_query only for the namespaces whose list endpoints accept it.
nv::page_query() {
  local ns="$1" limit cursor page
  case "$ns" in
  v2)
    limit="$(nv::args_get limit)"
    cursor="$(nv::args_get cursor)"
    [[ -z "$limit" ]] || nv::require_uint "$limit" limit
    nv::query_params limit "$limit" cursor "$cursor"
    ;;
  v1)
    page="$(nv::args_get page)"
    limit="$(nv::args_get limit)"
    [[ -z "$page" ]] || nv::require_uint "$page" page
    [[ -z "$limit" ]] || nv::require_uint "$limit" limit
    nv::query_params pageNo "$page" pageSize "$limit"
    ;;
  *) nv::usage "unknown pagination namespace: '$ns'" ;;
  esac
}

# Surface a v2 envelope's next-cursor to stderr so --json stdout stays clean.
# Arguments:
#   $1 - envelope: the raw v2 list response ({"data":…, "next_cursor":…, "has_more":…})
# Returns:
#   0 - always; silent unless has_more is true AND next_cursor is non-empty
nv::more_hint() {
  local envelope="$1" more next
  [[ -n "$envelope" ]] || return 0
  more="$(printf '%s' "$envelope" | jq -r '.has_more // false' 2>/dev/null)" || return 0
  [[ "$more" == "true" ]] || return 0
  next="$(printf '%s' "$envelope" | jq -r '.next_cursor // empty' 2>/dev/null)"
  [[ -n "$next" ]] || return 0
  nv::info "more items available — repeat with --cursor '$next'"
}

# Slice a JSON array in place (nameref $1) by --limit / --cursor. A non-array
# payload is left untouched (so object-wrapped or single records pass through).
# Client-side only — used by `nv api` against endpoints that ignore pagination
# params; the resource verbs use the server-side shapes above. Bad --limit values
# call nv::usage (exit 2) in the caller's shell — the caller must not wrap this
# in command substitution.
nv::paginate() {
  local -n paginate_out="$1"
  local limit cursor
  limit="$(nv::args_get limit)"
  cursor="$(nv::args_get cursor)"
  [[ -z "$limit" ]] || nv::require_uint "$limit" limit
  local take="${limit:-0}"
  paginate_out="$(printf '%s' "$paginate_out" | jq -c \
    --argjson take "$take" \
    'if type == "array"
     then (if $take > 0 then .[0:$take] else . end)
     else . end')" || return 1
}
