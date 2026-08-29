#!/usr/bin/env bash
# Novita HTTP clients — namespace-addressed (v2/v1) wrappers plus the
# per-endpoint serverless invoke. Thin facades over nv::api_call in
# lib/transport.sh; all curl lives in the shared transport module. Sourced by
# bin/nv; not executed directly.
# shellcheck source=transport.sh
[[ -n "${_NV_HTTP:-}" ]] && return 0
_NV_HTTP=1

# Emit the captured response: die on a curl transport failure or HTTP >= 400
# (with the API's error message when present), otherwise print the body. The
# exit code honours the contract: 404 -> not-found (4), 401/403 rejected key ->
# auth (3), any other >= 400 -> general error (1). $1 is the temp file holding
# the response body; $2/$3 the method/path for messages.
_nv_http_emit() {
  local tmp="$1" method="$2" path="$3"
  local status="$_NV_CURL_STATUS"
  # SIGINT (curl 130) mid-request: exit quietly as "interrupted" (130) rather
  # than a bogus transport error; the EXIT trap (_tmp_cleanup) removes temp files.
  if ((status == 130)); then
    rm -f -- "$tmp"
    exit 130
  fi
  if ((status == 0)); then
    rm -f -- "$tmp"
    nv::die "curl transport error: $method $path"
  fi
  if ((status >= 400)); then
    local msg err
    # Novita error bodies vary: {"message": …} on v2, {"error": …} or
    # {"reason": …} elsewhere. String-typed only — an object .error would dump
    # minified JSON at the user.
    msg="$(jq -rc 'if (.error | type) == "string" then .error elif .message then .message elif .reason then .reason elif .title then .title else empty end' "$tmp" 2>/dev/null || true)"
    rm -f -- "$tmp"
    err="Novita $method $path -> HTTP $status${msg:+: $msg}"
    _nv_exit_for_status "$status" "$err"
  fi
  cat "$tmp"
  rm -f -- "$tmp"
}

# Shared buffered call against a namespace base: preflight, dispatch through
# nv::api_call, then apply the emit policy. All public clients below build on
# this.
# Arguments:
#   $1 - ns: API namespace (v2 | v1)
#   $2 - method: HTTP method (GET/POST/DELETE/...)
#   $3 - path: namespace path (e.g. /instances, "/instances/$id")
#   $4 - body: optional JSON request body
#   $5 - max_time: optional --max-time seconds (default NV_TIMEOUT_API)
# Returns:
#   0 - success; prints the response to stdout
#   1 - transport/HTTP error (dies)
nv::_http_ns() {
  local ns="$1" method="$2" path="$3" body="${4:-}" max="${5:-}"
  nv::require_api_key
  nv::require_cmd curl
  local tmp
  _mktemp tmp
  nv::api_call "$ns" "$method" "$path" "$body" "$max" >"$tmp" || true
  _nv_http_emit "$tmp" "$method" "$path"
}

# v2 call (https://api.novita.ai/gpus/v2 — instances, endpoints, products,
# templates, regions; snake_case bodies, cursor pagination).
# Arguments:
#   $1 - method: HTTP method
#   $2 - path: v2 path (e.g. /instances)
#   $3 - body: optional JSON request body
#   $4 - max_time: optional --max-time seconds (default 120)
nv::http() {
  nv::_http_ns v2 "$1" "$2" "${3:-}" "${4:-}"
}

# v1 call (https://api.novita.ai/gpu-instance/openapi/v1 — clusters, network
# storage, repository auths; camelCase bodies, pageNo pagination).
# Arguments:
#   $1 - method: HTTP method
#   $2 - path: v1 path (e.g. /clusters, /networkstorages/list)
#   $3 - body: optional JSON request body
#   $4 - max_time: optional --max-time seconds (default 120)
nv::http_v1() {
  nv::_http_ns v1 "$1" "$2" "${3:-}" "${4:-}"
}

# Descriptor-aware dispatch: route through the namespace the current resource
# descriptor (_resource_meta in lib/resource.sh) declared. Used by the shared
# resource verbs so their call sites stay namespace-blind.
nv::res_http() {
  if [[ "${NV_RES_NS:-v2}" == "v1" ]]; then
    nv::http_v1 "$@"
  else
    nv::http "$@"
  fi
}

# Absolute-URL call for the serverless invoke: each endpoint record carries its
# own `url` field (a customer-owned host), so jobs are POSTed there verbatim
# rather than to a shared data-plane host. The route blocks on job completion,
# so the default --max-time is NV_TIMEOUT_INVOKE (300 s); $4 overrides it.
# Arguments:
#   $1 - method: HTTP method (POST for a job submit)
#   $2 - url: the endpoint's own invoke URL (must be https unless
#             NV_ALLOW_INSECURE_HTTP is set — enforced here, not only for the
#             namespace bases, because the key crosses the wire either way)
#   $3 - body: optional JSON request body (the job payload)
#   $4 - max_time: optional --max-time seconds (default 300)
# Returns:
#   0 - success; prints the response to stdout
#   1 - transport/HTTP error (dies)
nv::http_url() {
  local method="$1" url="$2" body="${3:-}" max="${4:-$NV_TIMEOUT_INVOKE}"
  case "$url" in
  https://*) ;;
  *)
    [[ -n "${NV_ALLOW_INSECURE_HTTP:-}" ]] ||
      nv::die "refusing insecure HTTP invoke target ($url); set NV_ALLOW_INSECURE_HTTP=1 to override"
    ;;
  esac
  nv::require_api_key
  nv::require_cmd curl
  local tmp
  _mktemp tmp
  _curl_json "$url" "$method" "$body" "$max" >"$tmp" || true
  _nv_http_emit "$tmp" "$method" "$url"
}

# Build a query string from alternating key/value pairs; empty values are
# skipped. Prints nothing (not "?") when no pair survives, so the caller can
# splice the result straight onto a path.
#
# Values go through jq's @uri, which encodes everything outside the unreserved
# set, then ',' and ':' are decoded back. RFC 3986 §3.4 allows both unencoded in
# a query, and they are the only reserved characters this CLI emits — csv
# filters and timestamps. Leaving them readable keeps logged URLs and error
# messages legible. Everything else stays encoded: '+' in particular must remain
# %2B or a '+00:00' offset decodes as a space, and '&'/'='/';' would split the
# query itself.
nv::query_params() {
  local q='' k v enc
  while (($# >= 2)); do
    k="$1"
    v="$2"
    shift 2
    [[ -n "$v" ]] || continue
    enc="$(printf '%s' "$v" | jq -Rr @uri)"
    enc="${enc//%2C/,}"
    enc="${enc//%3A/:}"
    q+="${q:+&}${k}=${enc}"
  done
  [[ -n "$q" ]] && printf '?%s' "$q"
}
