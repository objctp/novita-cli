#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  unset _NV_TRANSPORT _NV_HTTP
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/transport.sh"
  source "$RP_ROOT/lib/http.sh"
  eval "$_opts"
}

function set_up() {
  export NOVITA_API_KEY="nv-test"
  NV_BASE_V2="https://api.test/gpus/v2"
  NV_BASE_V1="https://api.test/gpu-instance/openapi/v1"
  NV_BASE_BASIC="https://api.test/openapi/v1"
  NV_BASE_ASYNC="https://async.test/v1"
  NV_ARGS=()
  CURL_CAPTURE="$(mktemp)"
}

function tear_down() {
  rm -f "$CURL_CAPTURE"
  unset -f curl
}

# curl double: record argv, answer with a fixed status/body.
_curl_double() {
  printf '%s\n' "$*" >>"$CURL_CAPTURE"
  local out=""
  while (($#)); do
    case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *) shift ;;
    esac
  done
  [[ -n "$out" ]] && printf '%s' "${CURL_BODY:-}" >"$out"
  printf '%s' "${CURL_STATUS:-200}"
}

function test_ns_base_resolves_v2_to_the_gpus_base() {
  assert_equals "https://api.test/gpus/v2" "$(_nv_ns_base v2)"
}

function test_ns_base_resolves_v1_to_the_openapi_base() {
  assert_equals "https://api.test/gpu-instance/openapi/v1" "$(_nv_ns_base v1)"
}

function test_ns_base_resolves_async_to_the_shared_invocation_host() {
  assert_equals "https://async.test/v1" "$(_nv_ns_base async)"
}

function test_ns_base_resolves_basic_to_the_billing_base() {
  assert_equals "https://api.test/openapi/v1" "$(_nv_ns_base basic)"
}

function test_ns_base_rejects_unknown_namespaces() {
  (_nv_ns_base v3 >/dev/null 2>&1)
  assert_exit_code 1
}

function test_ns_base_refuses_plaintext_without_override() {
  NV_BASE_V2="http://localhost:8080/gpus/v2"
  local out
  out="$(_nv_ns_base v2 2>&1)"
  assert_contains "refusing insecure HTTP" "$out"
  NV_BASE_V2="https://api.test/gpus/v2"
}

function test_ns_base_allows_plaintext_with_override() {
  NV_BASE_V2="http://localhost:8080/gpus/v2"
  NV_ALLOW_INSECURE_HTTP=1 _nv_ns_base v2 >/dev/null
  assert_equals "0" "$?"
  NV_BASE_V2="https://api.test/gpus/v2"
}

function test_http_routes_v2_paths_to_the_v2_base() {
  curl() { _curl_double "$@"; }
  CURL_BODY='{"data":[]}'
  nv::http GET /instances >/dev/null 2>&1
  assert_contains "https://api.test/gpus/v2/instances" "$(<"$CURL_CAPTURE")"
}

function test_http_v1_routes_paths_to_the_v1_base() {
  curl() { _curl_double "$@"; }
  CURL_BODY='{"data":[]}'
  nv::http_v1 GET /clusters >/dev/null 2>&1
  assert_contains "https://api.test/gpu-instance/openapi/v1/clusters" "$(<"$CURL_CAPTURE")"
}

function test_http_async_routes_paths_to_the_shared_invocation_host() {
  curl() { _curl_double "$@"; }
  CURL_BODY='{"id":"job-1","status":"PENDING"}'
  nv::http_async POST /ep-1-my-app/run '{"input":{}}' >/dev/null 2>&1
  assert_contains "https://async.test/v1/ep-1-my-app/run" "$(<"$CURL_CAPTURE")"
}

function test_http_basic_routes_paths_to_the_billing_base() {
  curl() { _curl_double "$@"; }
  CURL_BODY='{"availableBalance":"1000000"}'
  nv::http_basic GET /billing/balance/detail >/dev/null 2>&1
  assert_contains "https://api.test/openapi/v1/billing/balance/detail" "$(<"$CURL_CAPTURE")"
}

function test_http_sends_bearer_header_from_a_temp_file_not_argv() {
  curl() { _curl_double "$@"; }
  CURL_BODY='{"data":[]}'
  nv::http GET /instances >/dev/null 2>&1
  # The auth header must travel via -H @file — the key never appears on argv.
  assert_contains "-H @/" "$(<"$CURL_CAPTURE")"
  assert_not_contains "nv-test" "$(<"$CURL_CAPTURE")"
}

function test_http_url_invokes_an_absolute_endpoint_url() {
  curl() { _curl_double "$@"; }
  CURL_BODY='{"id":"job-1"}'
  nv::http_url POST "https://customer.example/run" '{"input":{"prompt":"hi"}}' >/dev/null 2>&1
  assert_contains "https://customer.example/run" "$(<"$CURL_CAPTURE")"
}

function test_http_url_refuses_plaintext_without_override() {
  local out
  out="$(nv::http_url POST "http://customer.example/run" '' 2>&1)"
  assert_contains "refusing insecure HTTP invoke target" "$out"
}

function test_http_dies_with_api_message_on_error() {
  curl() { _curl_double "$@"; }
  CURL_STATUS=404
  CURL_BODY='{"message":"instance not found"}'
  local out
  out="$(nv::http GET /instances/none 2>&1)"
  assert_exit_code 4
  assert_contains "HTTP 404: instance not found" "$out"
}

function test_http_maps_401_to_auth_exit() {
  curl() { _curl_double "$@"; }
  CURL_STATUS=401
  CURL_BODY='{"message":"bad key"}'
  (nv::http GET /instances >/dev/null 2>&1)
  assert_exit_code 3
}
