#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/update_check.sh"
  eval "$_opts"
  # nv::version lives in bin/nv (not lib/); pin it so comparisons are
  # deterministic and no dev-checkout `git describe` leaks in.
  nv::version() { printf '%s' "${FAKE_NV_VERSION:-0.1.0}"; }
}

function set_up() {
  FAKE_NV_VERSION="0.1.0"
  NV_TMP_BASE="$(mktemp -d)"
  # The config home itself must not exist yet: the skip tests assert the check
  # bailed out BEFORE creating it.
  NV_CONFIG_HOME="$NV_TMP_BASE/novita"
  export NV_CONFIG_HOME
  NV_UPGRADE_REPO="test/nv"
}

function tear_down() {
  rm -rf "$NV_TMP_BASE"
}

function test_should_be_behind_when_the_latest_patch_is_newer() {
  nv::_version_is_behind 0.1.1
  assert_successful_code "$?"
}

function test_should_be_behind_when_the_latest_minor_is_newer() {
  nv::_version_is_behind 1.0.0
  assert_successful_code "$?"
}

function test_should_not_be_behind_when_versions_are_equal() {
  nv::_version_is_behind 0.1.0
  assert_general_error "$?"
}

function test_should_not_be_behind_when_the_installed_version_is_newer() {
  nv::_version_is_behind 0.0.9
  assert_general_error "$?"
}

function test_should_not_be_behind_for_a_dev_build() {
  FAKE_NV_VERSION="0.0.0-dev"
  nv::_version_is_behind 99.0.0
  assert_general_error "$?"
}

function test_should_skip_entirely_when_disabled_by_the_environment() {
  NV_NO_UPDATE_CHECK=1 nv::update_check pod
  assert_successful_code "$?"
  assert_directory_not_exists "$NV_CONFIG_HOME"
}

# stderr is not a TTY under bashunit, so the TTY gate must skip before any
# filesystem side effect — the same guarantee scripts and CI rely on.
function test_should_skip_for_non_tty_stderr() {
  nv::update_check pod </dev/null >/dev/null 2>&1
  assert_successful_code "$?"
  assert_directory_not_exists "$NV_CONFIG_HOME"
}

function test_should_resolve_a_symlink_chain_to_the_final_target() {
  local real="$NV_CONFIG_HOME/.nv/bin/nv" link1="$NV_CONFIG_HOME/bin/nv" link2="$NV_CONFIG_HOME/nv"
  mkdir -p "$(dirname "$real")" "$(dirname "$link1")"
  printf '#!/usr/bin/env bash\n' >"$real"
  chmod +x "$real"
  ln -s "$real" "$link1"
  ln -s "$link1" "$link2"
  assert_equals "$real" "$(nv::_resolve "$link2")"
}

function test_should_detect_a_bash_install_under_the_home_dir() {
  local real="$NV_CONFIG_HOME/.nv/bin/nv"
  mkdir -p "$(dirname "$real")"
  printf '#!/usr/bin/env bash\n' >"$real"
  chmod +x "$real"
  assert_equals "bash" "$(PATH="$NV_CONFIG_HOME/.nv/bin:$PATH" nv::_detect_install_method)"
}

function test_should_detect_unknown_when_nv_is_off_the_path() {
  assert_equals "unknown" "$(PATH="/nonexistent" nv::_detect_install_method)"
}
