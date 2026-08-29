#!/usr/bin/env bash
#
# Raw namespaced call over nv's own transport.
#
# This is the same transport every resource verb uses, exposed for scripting
# and ad-hoc calls: it resolves the method, namespace, path, body, and optional
# jq filter, then delegates to nv::http / nv::http_v1 — all curl, auth, timeout
# and error policy live in lib/transport.sh behind that seam. It prints the
# response body, and dies on HTTP 400 or above with the API's own message.
#
# Usage: nv api <METHOD> <path> [--body <json>] [--ns v2|v1]
#               [--jq <filter>] [--limit N] [--cursor <c>]
#
# Arguments:
#   <METHOD>     HTTP method: GET/POST/PUT/DELETE/... (case-insensitive)
#   <path>       path under the namespace base (a leading / is optional)
#
# Options:
#   --body <json>  request body; prefix with @ to read a file
#   --ns v2|v1     v2 = /gpus/v2 (default) | v1 = /gpu-instance/openapi/v1
#   --jq <filter>  jq filter applied to the response (implies JSON output)
#   --limit N      cap the number of (top-level-array) items returned
#
# Examples:
# # List instances (v2 default)
# $ nv api GET /instances
# # List clusters (v1 namespace)
# $ nv api GET /clusters --ns v1
# # Create an instance from a JSON body
# $ nv api POST /instances --body '{"product_id":"…","image":"…"}'
#

_api_help() {
  cat <<'EOF'
Usage: nv api <METHOD> <path> [flags]

Raw call to the Novita API — the same transport nv's resource verbs use,
exposed for scripting and ad-hoc calls. Prints the response body; dies on
HTTP >= 400 with the API's error message.

  <METHOD>     HTTP method (GET/POST/PUT/DELETE/...); case-insensitive
  <path>       path under the namespace base (a leading / is optional)
  --body       request body (JSON string); prefix with @ to read a file
  --ns         v2 = /gpus/v2 (default) | v1 = /gpu-instance/openapi/v1
  --jq         jq filter applied to the response (implies JSON output)
               note: jq's `env` exposes the shell environment, including your
               NOVITA_API_KEY — never run `nv api … --jq 'env'` on a shared
               terminal or in logs you don't control.
  --limit      cap the number of (top-level-array) items returned

Examples:
  nv api GET /instances
  nv api GET /clusters --ns v1
  nv api POST /instances --body '{"product_id":"…","image":"…"}'
EOF
}

nv::cmd_api() {
  local method="${1:-}"
  if [[ "$method" == "-h" || "$method" == "--help" || "$method" == "help" ]]; then
    _api_help
    return 0
  fi
  shift || true
  nv::args_parse "$@"
  nv::args_has help && {
    _api_help
    return 0
  }
  [[ -n "$method" ]] || nv::usage "usage: nv api <METHOD> <path> [--body <json>] [--ns v2|v1] [--jq <filter>]"
  method="$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')"
  local path
  nv::require_pos path "usage: nv api $method <path>"
  [[ "$path" == /* ]] || path="/$path"
  local ns body jqf
  ns="$(nv::args_get ns v2)"
  body="$(nv::args_get body)"
  jqf="$(nv::args_get jq)"
  if [[ -n "$body" && "$body" == @* ]]; then
    body="$(<"${body#@}")" || nv::die "cannot read --body file: ${body#@}"
  fi
  local out
  case "$ns" in
  v2) out="$(nv::http "$method" "$path" "$body")" ;;
  v1) out="$(nv::http_v1 "$method" "$path" "$body")" ;;
  *) nv::usage "unknown --ns '$ns' (v2|v1)" ;;
  esac
  nv::paginate out
  if [[ -n "$jqf" ]]; then
    printf '%s' "$out" | jq -r "$jqf"
  else
    printf '%s' "$out"
  fi
}
