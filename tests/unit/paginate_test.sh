#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/paginate.sh"
  eval "$_opts"
}

# v2: server-side cursor pagination — limit + opaque cursor forwarded verbatim.
function test_page_query_v2_forwards_limit_and_cursor() {
  nv::args_parse --limit 5 --cursor abc
  assert_equals "?limit=5&cursor=abc" "$(nv::page_query v2)"
}

function test_page_query_v2_prints_nothing_without_flags() {
  nv::args_parse
  assert_equals "" "$(nv::page_query v2)"
}

function test_page_query_v2_rejects_non_numeric_limit() {
  nv::args_parse --limit ten
  (nv::page_query v2 >/dev/null 2>&1)
  assert_exit_code 2
}

# v1: pageNo/pageSize — --page and --limit map onto the v1 param names.
function test_page_query_v1_maps_page_and_limit() {
  nv::args_parse --page 2 --limit 10
  assert_equals "?pageNo=2&pageSize=10" "$(nv::page_query v1)"
}

function test_page_query_v1_prints_nothing_without_flags() {
  nv::args_parse
  assert_equals "" "$(nv::page_query v1)"
}

function test_page_query_rejects_unknown_namespace() {
  nv::args_parse
  (nv::page_query v3 >/dev/null 2>&1)
  assert_exit_code 2
}

# The v2 next-cursor hint goes to stderr so --json stdout stays clean.
function test_more_hint_prints_next_cursor_to_stderr() {
  local out
  nv::args_parse
  out="$(nv::more_hint '{"data":[],"next_cursor":"c-2","has_more":true}' 2>&1 1>/dev/null)"
  assert_contains "--cursor 'c-2'" "$out"
}

function test_more_hint_silent_when_no_more_pages() {
  local out
  nv::args_parse
  out="$(nv::more_hint '{"data":[],"next_cursor":"","has_more":false}' 2>&1 1>/dev/null)"
  assert_equals "" "$out"
}

function test_more_hint_silent_on_non_envelope_payloads() {
  local out
  nv::args_parse
  out="$(nv::more_hint '{"id":"x"}' 2>&1 1>/dev/null)"
  assert_equals "" "$out"
}

# Client-side slicer for `nv api` output.
function test_paginate_slices_array_by_limit() {
  # shellcheck disable=SC2178 # nameref write-back keeps this a JSON string
  local arr='[1,2,3,4,5]'
  nv::args_parse --limit 2
  nv::paginate arr
  # shellcheck disable=SC2128 # nameref write-back keeps this a JSON string
  assert_equals '[1,2]' "$arr"
}

function test_paginate_leaves_objects_alone() {
  # shellcheck disable=SC2178 # nameref write-back keeps this a JSON string
  local obj='{"id":"a"}'
  nv::args_parse --limit 2
  nv::paginate obj
  # shellcheck disable=SC2128 # nameref write-back keeps this a JSON string
  assert_equals '{"id":"a"}' "$obj"
}
