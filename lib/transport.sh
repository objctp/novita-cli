#!/usr/bin/env bash
# Novita transport — the single curl implementation shared by every client.
# Novita serves the whole GPU cloud from ONE host (https://api.novita.ai) under
# TWO namespaces: v2 (/gpus/v2, snake_case, cursor-paginated) and v1
# (/gpu-instance/openapi/v1, camelCase, pageNo-paginated). All auth-header,
# payload, timeout, and status handling lives here; the public clients in
# lib/http.sh are thin facades over nv::api_call. Sourced by bin/nv.
[[ -n "${_NV_TRANSPORT:-}" ]] && return 0
_NV_TRANSPORT=1

# Last HTTP status from _curl_json, read by the public wrappers to apply their
# die/soft policy. Module-global: set inside _curl_json, read by callers.
declare -g _NV_CURL_STATUS=200

# TLS certificate verification opt-out: when nv runs from inside an instance
# whose CA bundle can't validate api.novita.ai, curl fails with "certificate
# signed by unknown authority". --insecure (alias -k), or NV_INSECURE_TLS=1, pass
# curl -k. This is orthogonal to NV_ALLOW_INSECURE_HTTP: that guard refuses
# *plaintext* (http://) transport, whereas --insecure only relaxes the cert chain
# check over an already-encrypted https:// link. Warned once per process.
declare -g _NV_INSECURE_WARNED=0

_nv_insecure_enabled() {
  [[ -n "${NV_ARGS[insecure]:-}" || -n "${NV_INSECURE_TLS:-}" ]]
}

_nv_insecure_warn() {
  ((_NV_INSECURE_WARNED)) && return 0
  _NV_INSECURE_WARNED=1
  nv::warn "TLS certificate verification disabled (--insecure): traffic stays encrypted but the server identity is NOT authenticated"
}

# Base URL for an API namespace. Resolved at call time so env overrides of
# NV_BASE_V2 / NV_BASE_V1 (set in lib/common.sh) take effect. The serverless
# invoke route has no namespace base of its own — each endpoint record carries
# its own `url` field, invoked verbatim (see nv::http_url in lib/http.sh).
# Every client routes through here, so the insecure-transport guard below
# covers all of them.
_nv_ns_base() {
  local base
  case "$1" in
  v2) base="${NV_BASE_V2:-https://api.novita.ai/gpus/v2}" ;;
  v1) base="${NV_BASE_V1:-https://api.novita.ai/gpu-instance/openapi/v1}" ;;
  *) return 1 ;;
  esac
  # Refuse plaintext transport: the Bearer key would cross the wire in cleartext.
  # NV_ALLOW_INSECURE_HTTP=1 opts out for local/test setups only.
  case "$base" in
  https://*) ;;
  *)
    [[ -n "${NV_ALLOW_INSECURE_HTTP:-}" ]] ||
      nv::die "refusing insecure HTTP transport for the '$1' namespace ($base); set NV_ALLOW_INSECURE_HTTP=1 to override"
    ;;
  esac
  printf '%s' "$base"
}

# Default --max-time (seconds) per route. The serverless invoke blocks on job
# completion, so it gets a longer budget than the control namespaces.
_nv_ns_timeout() {
  case "$1" in
  invoke) printf '%s' "$NV_TIMEOUT_INVOKE" ;;
  *) printf '%s' "$NV_TIMEOUT_API" ;;
  esac
}

# The one curl implementation. Never dies: prints the response body to stdout,
# records the HTTP status in _NV_CURL_STATUS, and returns non-zero only on a curl
# transport failure (status left at 000). Auth header and request body travel
# through temp files, not argv — argv is visible in `ps` for curl's lifetime, so
# -H/--data would leak the API key (and, on a serverless invoke, the job payload).
_curl_json() {
  local url="$1" method="$2" body="${3:-}" max_time="${4:-$NV_TIMEOUT_API}"
  local hdr body_tmp tmp status out
  _mktemp hdr
  nv::auth_header >"$hdr"
  local -a args=(-sSL --connect-timeout "$NV_TIMEOUT_CONNECT" --max-time "$max_time" -X "$method" -H @"$hdr" -H 'Content-Type: application/json')
  if _nv_insecure_enabled; then
    _nv_insecure_warn
    args+=(-k)
  fi
  _mktemp tmp
  if [[ -n "$body" ]]; then
    _mktemp body_tmp
    printf '%s' "$body" >"$body_tmp"
    args+=(--data @"$body_tmp")
  fi
  args+=("$url")
  status="$(curl "${args[@]}" -o "$tmp" -w '%{http_code}')" || {
    rc=$?
    _nv_cleanup_tmp "$hdr" "$tmp" "${body_tmp:-}"
    # curl exit 130 == killed by SIGINT: surface as "interrupted" (exit 130),
    # never a bogus transport error. The emit helper (_nv_http_emit) checks
    # _NV_CURL_STATUS and bails quietly.
    if ((rc == 130)); then
      _NV_CURL_STATUS=130
    else
      _NV_CURL_STATUS=000
    fi
    return "$rc"
  }
  out="$(<"$tmp")"
  _nv_cleanup_tmp "$hdr" "$tmp" "${body_tmp:-}"
  _NV_CURL_STATUS="$status"
  printf '%s' "$out"
  return 0
}

# Remove the temp files a single curl call created. The request-body temp is
# only created when there is a body, so it may be empty (GET requests); passing
# an empty string to `rm -f` is harmless but sloppy, so we collect only the paths
# that were actually created into an array and remove those. Pure (no exit).
_nv_cleanup_tmp() {
  local hdr="$1" tmp="$2" body="${3:-}"
  local -a c=("$hdr" "$tmp")
  [[ -n "$body" ]] && c+=("$body")
  rm -f -- "${c[@]}"
}

# Namespace-addressed call: resolves <ns> to its base URL + default timeout,
# then delegates to _curl_json. Dies only on an unknown namespace (a programming
# error); transport/HTTP outcomes are left to the caller's die policy.
# Arguments:
#   $1 - ns: API namespace (v2 | v1)
#   $2 - method: HTTP method (GET/POST/DELETE/...)
#   $3 - path: namespace path (e.g. /instances, "/instances/$id")
#   $4 - body: optional JSON request body
#   $5 - max_time: optional --max-time seconds
nv::api_call() {
  local ns="$1" method="$2" path="$3" body="${4:-}" max="${5:-}"
  local base timeout
  base="$(_nv_ns_base "$ns")" || nv::die "unknown API namespace: '$ns'"
  timeout="$(_nv_ns_timeout "${6:-api}")"
  max="${max:-$timeout}"
  _curl_json "$base$path" "$method" "$body" "$max"
}
