#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/commands/upgrade.sh"
  eval "$_opts"
  # nv::version lives in bin/nv (not lib/); pin it so the "nv x -> y" line and
  # comparisons are deterministic.
  nv::version() { printf '%s' "0.1.0"; }
}

function set_up() {
  NV_UPGRADE_REPO="test/nv"
  UPG_CAPTURE="$(mktemp)"
  UPG_RAN="$(mktemp)"
  UPG_ARGS="$(mktemp)"
  # curl double: record argv, write a benign installer that logs its argv.
  curl() {
    printf '%s\n' "$*" >>"$UPG_CAPTURE"
    local -a a=("$@")
    local i out=""
    for ((i = 0; i < ${#a[@]}; i++)); do
      [[ "${a[i]}" == "-o" ]] && out="${a[i + 1]}"
    done
    [[ -n "$out" ]] && printf 'echo installer-ran >> %s\nprintf "%%s\\n" "$*" >> %s\n' "$(printf '%q' "$UPG_RAN")" "$(printf '%q' "$UPG_ARGS")" >"$out"
    return 0
  }
}

function tear_down() {
  rm -f "$UPG_CAPTURE" "$UPG_RAN" "$UPG_ARGS"
  rm -f "${_NV_TEMPS[@]}" 2>/dev/null
  _NV_TEMPS=()
  unset -f curl
}

function test_upgrade_downloads_main_installer_when_no_version_given() {
  nv::cmd_upgrade >/dev/null 2>&1
  assert_contains "https://raw.githubusercontent.com/test/nv/main/install.sh" "$(<"$UPG_CAPTURE")"
}

function test_upgrade_pins_the_installer_to_the_tagged_version() {
  nv::args_parse --version 1.2.3
  nv::cmd_upgrade --version 1.2.3 >/dev/null 2>&1
  assert_contains "https://raw.githubusercontent.com/test/nv/v1.2.3/install.sh" "$(<"$UPG_CAPTURE")"
}

function test_upgrade_strips_a_leading_v_before_building_the_url() {
  nv::cmd_upgrade --version v1.2.3 >/dev/null 2>&1
  assert_contains "https://raw.githubusercontent.com/test/nv/v1.2.3/install.sh" "$(<"$UPG_CAPTURE")"
}

# The downloaded installer runs with the pinned version forwarded, so a
# downgrade installs that tag's payload with that tag's own installer.
function test_upgrade_executes_the_downloaded_installer_with_the_version() {
  nv::cmd_upgrade --version 1.2.3 >/dev/null 2>&1
  assert_contains "installer-ran" "$(<"$UPG_RAN")"
  assert_contains "--version 1.2.3" "$(<"$UPG_ARGS")"
}

function test_upgrade_rejects_a_malformed_version_before_any_download() {
  (nv::cmd_upgrade --version 1.2 >/dev/null 2>&1)
  assert_exit_code 2
  assert_equals "" "$(<"$UPG_CAPTURE")"
}

function test_upgrade_dies_when_the_installer_download_fails() {
  curl() { return 1; }
  (nv::cmd_upgrade >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  nv::cmd_upgrade help >"$tmp" 2>/dev/null
  assert_contains "Usage: nv upgrade" "$(<"$tmp")"
  rm -f "$tmp"
}
