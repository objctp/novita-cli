#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/args.sh"
  eval "$_opts"
}

function test_parses_flag_with_equals() {
  nv::args_parse --name "my-pod"
  assert_equals "my-pod" "$(nv::args_get name)"
}

function test_parses_flag_with_separate_value() {
  nv::args_parse --name my-pod
  assert_equals "my-pod" "$(nv::args_get name)"
}

function test_parses_bool_flag() {
  nv::args_parse --json
  assert_equals "yes" "$(nv::args_has json && echo yes)"
}

function test_collects_positionals_in_order() {
  nv::args_parse first second third
  assert_equals "first" "$(nv::args_pos)"
  assert_equals "second" "$(nv::args_pos_at 1)"
  assert_equals "third" "$(nv::args_pos_at 2)"
}

function test_repeatable_env_accumulates_newline_joined() {
  nv::args_parse --env A=1 --env B=2
  assert_equals "A=1
B=2" "$(nv::args_get env)"
}

function test_alias_copies_into_free_canonical() {
  nv::args_parse --product-id prod-1
  assert_equals "prod-1" "$(nv::args_get product)"
}

function test_alias_never_overrides_explicit_canonical() {
  nv::args_parse --product prod-1 --product-id prod-2
  assert_equals "prod-1" "$(nv::args_get product)"
}

function test_repeatable_alias_fills_the_canonical() {
  nv::args_parse --candidate-regions r1,r2
  assert_equals "r1,r2" "$(nv::args_get region)"
}

function test_alias_is_ignored_when_canonical_is_set() {
  nv::args_parse --region r1 --candidate-regions r2
  assert_equals "r1" "$(nv::args_get region)"
}

function test_flag_without_value_exits_usage() {
  (nv::args_parse --name >/dev/null 2>&1)
  assert_exit_code 2
}

function test_require_pos_exits_usage_when_missing() {
  local out
  out="$(nv::require_pos id "usage: nv pod get <id>" 2>&1)"
  assert_exit_code 2
  assert_contains "usage: nv pod get <id>" "$out"
}
