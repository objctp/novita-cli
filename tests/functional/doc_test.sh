#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/doc.sh"
  source "$RP_ROOT/commands/doc.sh"
  eval "$_opts"
}

function test_catalogue_lists_every_command_with_a_summary() {
  local out
  out="$(nv::cmd_doc)"
  assert_contains "nv pod" "$out"
  assert_contains "nv serverless" "$out"
  assert_contains "nv volume" "$out"
  assert_contains "nv auth" "$out"
}

function test_command_page_shows_intro_and_verb_index() {
  local out
  out="$(nv::cmd_doc serverless)"
  assert_contains "nv serverless" "$out"
  assert_contains "Verbs:" "$out"
  assert_contains "create" "$out"
  assert_contains "run" "$out"
}

function test_verb_page_renders_the_doc_block() {
  local out
  out="$(nv::cmd_doc serverless create)"
  assert_contains "nv serverless create" "$out"
  assert_contains "idempotent by name" "$out"
  assert_contains "POST /gpus/v2/endpoints" "$out"
}

function test_prefix_abbreviation_resolves_a_command() {
  local out
  out="$(nv::cmd_doc serv 2>/dev/null)"
  assert_contains "nv serverless" "$out"
}

function test_unknown_command_reports_no_match() {
  local out
  out="$(nv::cmd_doc nope)"
  assert_contains "no documentation matches 'nope'" "$out"
}

function test_unknown_verb_reports_no_match() {
  local out
  out="$(nv::cmd_doc pod frobnicate)"
  assert_contains "no verb 'frobnicate' for command 'pod'" "$out"
}

function test_doc_page_marks_unverified_routes() {
  local out
  out="$(nv::cmd_doc template create)"
  assert_contains "route unverified" "$out"
}
