#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# `nv auth` account store — exercises login/logout/switch/list/status against a
# throwaway NV_CONFIG_HOME.

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/commands/auth.sh"
  eval "$_opts"
}

function set_up() {
  # Rebuild the credential store in a temp config home for every test.
  NV_CONFIG_HOME="$(mktemp -d)"
  NV_CREDS_DIR="$NV_CONFIG_HOME/credentials.d"
  NV_ACTIVE_FILE="$NV_CONFIG_HOME/active"
  unset NOVITA_API_KEY NOVITA_API_KEY_FILE
  NV_ENV_SRC=()
}

function tear_down() {
  rm -rf "$NV_CONFIG_HOME"
}

function test_login_stores_the_key_and_marks_it_active() {
  nv::args_parse --name work --api-key nv-key-123
  _auth_login >/dev/null 2>&1
  assert_file_exists "$NV_CREDS_DIR/work"
  assert_equals "work" "$(cat "$NV_ACTIVE_FILE")"
  assert_equals "nv-key-123" "$(grep '^NOVITA_API_KEY=' "$NV_CREDS_DIR/work" | cut -d= -f2-)"
}

# Permission bits, portable across the BSD (macOS) and GNU (Linux) stat
# dialects — same probe as lib/common.sh's _warn_if_world_readable.
function _perms() {
  if stat -f '%Lp' /dev/null >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

function test_account_file_is_mode_600_and_dir_700() {
  nv::args_parse --api-key nv-key-123
  _auth_login >/dev/null 2>&1
  assert_equals "600" "$(_perms "$NV_CREDS_DIR/default")"
  assert_equals "700" "$(_perms "$NV_CREDS_DIR")"
}

function test_login_reads_the_key_from_stdin_when_piped() {
  printf 'nv-piped-key\n' | {
    nv::args_parse
    _auth_login 2>/dev/null
  }
  assert_equals "nv-piped-key" "$(grep '^NOVITA_API_KEY=' "$NV_CREDS_DIR/default" | cut -d= -f2-)"
}

function test_login_preserves_other_lines_on_relogin() {
  nv::args_parse --api-key nv-first
  _auth_login >/dev/null 2>&1
  printf 'MY_EXTRA_VAR=1\n' >>"$NV_CREDS_DIR/default"
  nv::args_parse --api-key nv-second
  _auth_login >/dev/null 2>&1
  assert_contains "MY_EXTRA_VAR=1" "$(<"$NV_CREDS_DIR/default")"
  assert_equals "nv-second" "$(grep '^NOVITA_API_KEY=' "$NV_CREDS_DIR/default" | cut -d= -f2-)"
}

function test_logout_removes_the_active_account_and_switches() {
  nv::args_parse --name a --api-key k1
  _auth_login >/dev/null 2>&1
  nv::args_parse --name b --api-key k2
  _auth_login >/dev/null 2>&1
  # No --name: the ACTIVE account (b) is removed, and the store switches to a.
  nv::args_parse
  _auth_logout >/dev/null 2>&1
  assert_file_not_exists "$NV_CREDS_DIR/b"
  assert_equals "a" "$(cat "$NV_ACTIVE_FILE")"
}

function test_logout_with_name_removes_that_account_only() {
  nv::args_parse --name a --api-key k1
  _auth_login >/dev/null 2>&1
  nv::args_parse --name b --api-key k2
  _auth_login >/dev/null 2>&1
  nv::args_parse --name a
  _auth_logout "$(nv::args_get name)" >/dev/null 2>&1
  assert_file_not_exists "$NV_CREDS_DIR/a"
  assert_file_exists "$NV_CREDS_DIR/b"
  # a was not active, so the active pointer stays on b.
  assert_equals "b" "$(cat "$NV_ACTIVE_FILE")"
}

function test_switch_rejects_unknown_accounts() {
  (_auth_switch work >/dev/null 2>&1)
  assert_exit_code 1
}

function test_status_reports_the_active_account_and_masked_key() {
  nv::args_parse --name prod --api-key nv-abcdef123456
  _auth_login >/dev/null 2>&1
  local out
  out="$(nv::cmd_auth status 2>/dev/null)"
  assert_contains "prod" "$out"
  assert_contains "configured" "$out"
  assert_not_contains "nv-abcdef123456" "$out"
}

function test_help_lists_the_verbs() {
  local out
  out="$(nv::cmd_auth help 2>/dev/null)"
  assert_contains "Usage: nv auth" "$out"
  assert_contains "login" "$out"
  assert_contains "switch" "$out"
}
