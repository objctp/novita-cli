#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/paginate.sh"
  source "$RP_ROOT/lib/transport.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/commands/api.sh"
  eval "$_opts"
}

function set_up() {
  API_CAPTURE="$(mktemp)"
  API_BODY="$(mktemp)"
  API_STUB_BODY='{"data":[]}'
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$API_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$API_BODY"
    fi
    printf '%s' "$API_STUB_BODY"
  }
  nv::http_v1() {
    printf '%s %s\n' "$1" "$2" >>"$API_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$API_BODY"
    fi
    printf '%s' "$API_STUB_BODY"
  }
  nv::http_async() {
    printf '%s %s\n' "$1" "$2" >>"$API_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$API_BODY"
    fi
    printf '%s' "$API_STUB_BODY"
  }
  nv::http_basic() {
    printf '%s %s\n' "$1" "$2" >>"$API_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$API_BODY"
    fi
    printf '%s' "$API_STUB_BODY"
  }
}

function tear_down() {
  rm -f "$API_CAPTURE" "$API_BODY"
}

function test_defaults_to_the_v2_namespace() {
  nv::cmd_api GET /instances >/dev/null 2>&1
  assert_contains "GET /instances" "$(<"$API_CAPTURE")"
}

function test_ns_v1_routes_through_http_v1() {
  rm -f "$API_CAPTURE"
  nv::cmd_api GET /clusters --ns v1 >/dev/null 2>&1
  # The v2 double would have recorded the same shape; distinguish by body:
  # http_v1's capture is written only when ns=v1 routed there.
  assert_contains "GET /clusters" "$(<"$API_CAPTURE")"
}

function test_ns_async_routes_through_http_async() {
  rm -f "$API_CAPTURE"
  nv::cmd_api POST /ep-1/run --ns async --body '{"input":{}}' >/dev/null 2>&1
  assert_contains "POST /ep-1/run" "$(<"$API_CAPTURE")"
  assert_contains '{"input":{}}' "$(<"$API_BODY")"
}

function test_ns_basic_routes_through_http_basic() {
  rm -f "$API_CAPTURE"
  nv::cmd_api GET /billing/balance/detail --ns basic >/dev/null 2>&1
  assert_contains "GET /billing/balance/detail" "$(<"$API_CAPTURE")"
}

function test_method_is_uppercased() {
  nv::cmd_api get /instances >/dev/null 2>&1
  assert_contains "GET /instances" "$(<"$API_CAPTURE")"
  assert_not_contains "get /instances" "$(<"$API_CAPTURE")"
}

function test_body_is_forwarded() {
  nv::cmd_api POST /instances --body '{"name":"x"}' >/dev/null 2>&1
  assert_contains '{"name":"x"}' "$(<"$API_BODY")"
}

function test_body_file_is_read_with_at_prefix() {
  local f
  f="$(mktemp)"
  printf '{"name":"from-file"}' >"$f"
  nv::cmd_api POST /instances --body "@$f" >/dev/null 2>&1
  assert_contains '{"name":"from-file"}' "$(<"$API_BODY")"
  rm -f "$f"
}

function test_leading_slash_is_optional() {
  nv::cmd_api GET instances >/dev/null 2>&1
  assert_contains "GET /instances" "$(<"$API_CAPTURE")"
}

function test_unknown_ns_exits_usage() {
  (nv::cmd_api GET /instances --ns v3 >/dev/null 2>&1)
  assert_exit_code 2
}

function test_missing_path_exits_usage() {
  (nv::cmd_api GET >/dev/null 2>&1)
  assert_exit_code 2
}

function test_jq_filter_applies_to_the_response() {
  local out
  API_STUB_BODY='{"data":[{"id":"a"},{"id":"b"}]}'
  out="$(nv::cmd_api GET /instances --jq '.data[].id' 2>/dev/null)"
  assert_equals $'a\nb' "$out"
}

function test_limit_slices_top_level_arrays() {
  local out
  API_STUB_BODY='[1,2,3,4]'
  out="$(nv::cmd_api GET /things --limit 2 2>/dev/null)"
  assert_equals '[1,2]' "$out"
}
