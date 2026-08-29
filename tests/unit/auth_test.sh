#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
  unset NOVITA_API_KEY NOVITA_API_KEY_FILE
}

function tear_down() {
  rm -f "$OUT"
}

function test_token_from_env() {
  NOVITA_API_KEY="nv-env123" nv::auth_token >"$OUT"
  assert_equals "nv-env123" "$(<"$OUT")"
}

function test_header_format_from_env() {
  NOVITA_API_KEY="nv-env123" nv::auth_header >"$OUT"
  assert_equals "Authorization: Bearer nv-env123" "$(<"$OUT")"
}

function test_token_from_file_trims_newline() {
  local f
  f="$(mktemp)"
  printf 'nv-file456\n' >"$f"
  NOVITA_API_KEY_FILE="$f" nv::auth_token >"$OUT"
  assert_equals "nv-file456" "$(<"$OUT")"
  rm -f "$f"
}

function test_file_missing_dies() {
  local out
  out="$(
    NOVITA_API_KEY_FILE=/no/such/file nv::auth_token 2>&1
    echo "exit=$?"
  )"
  assert_contains "missing file" "$out"
}

function test_no_source_dies_with_auth_exit() {
  local out rc
  out="$(nv::auth_token 2>&1)"
  rc=$?
  assert_contains "NOVITA_API_KEY unset" "$out"
  assert_equals "3" "$rc"
}

# L2: with `set -x` (bash -x), the key must not appear in the trace. Capture
# stderr (the trace) only — stdout (the key) is discarded. The env var is set
# BEFORE set -x: an assignment under xtrace echoes its own value.
function test_should_not_leak_key_in_xtrace_via_auth_token() {
  local err
  err="$(
    bash -c '
      source "'"$RP_ROOT"'/lib/common.sh"
      source "'"$RP_ROOT"'/lib/auth.sh"
      NOVITA_API_KEY="nv-secret"
      set -x
      nv::auth_token
    ' 2>&1 1>/dev/null
  )"
  assert_not_contains "nv-secret" "$err"
}

# The header build must equally keep the key out of an xtrace.
function test_should_not_leak_key_in_xtrace_via_auth_header() {
  local err
  err="$(
    bash -c '
      source "'"$RP_ROOT"'/lib/common.sh"
      source "'"$RP_ROOT"'/lib/auth.sh"
      NOVITA_API_KEY="nv-secret"
      set -x
      nv::auth_header
    ' 2>&1 1>/dev/null
  )"
  assert_not_contains "nv-secret" "$err"
}
