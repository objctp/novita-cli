#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  eval "$_opts"
}

function test_http_exit_code_maps_auth_statuses() {
  assert_equals "3" "$(nv::http_exit_code 401)"
  assert_equals "3" "$(nv::http_exit_code 403)"
}

function test_http_exit_code_maps_notfound() {
  assert_equals "4" "$(nv::http_exit_code 404)"
}

function test_http_exit_code_maps_other_client_errors_to_general() {
  assert_equals "1" "$(nv::http_exit_code 400)"
  assert_equals "1" "$(nv::http_exit_code 500)"
}

function test_http_exit_code_maps_success_to_zero() {
  assert_equals "0" "$(nv::http_exit_code 200)"
  assert_equals "0" "$(nv::http_exit_code 302)"
}

function test_unwrap_extracts_the_data_key() {
  assert_equals '[{"id":"a"},{"id":"b"}]' \
    "$(nv::unwrap data '{"data":[{"id":"a"},{"id":"b"}],"next_cursor":"","has_more":false,"total":2}')"
}

function test_unwrap_passes_arrays_through() {
  assert_equals '[{"id":"a"}]' "$(nv::unwrap data '[{"id":"a"}]')"
}

function test_unwrap_passes_objects_through() {
  assert_equals '{"id":"a"}' "$(nv::unwrap data '{"id":"a"}')"
}

function test_unwrap_reads_stdin_when_body_omitted() {
  assert_equals '[1]' "$(printf '{"data":[1]}' | nv::unwrap data)"
}

function test_extract_id_from_object_response() {
  local out=""
  nv::extract_id out '{"id":"abc-1"}' endpoint
  assert_equals "abc-1" "$out"
}

# v2 template create/update answer {"template_id": …}, not {"id": …}.
function test_extract_id_from_template_id_response() {
  local out=""
  nv::extract_id out '{"template_id":"tpl-001"}' template
  assert_equals "tpl-001" "$out"
}

# v1 network-storage create answers a BARE JSON STRING — the id IS the body.
function test_extract_id_from_bare_string_response() {
  local out=""
  nv::extract_id out '"d4e82677-3f80-4020-a731-d15b1c589aa8"' volume
  assert_equals "d4e82677-3f80-4020-a731-d15b1c589aa8" "$out"
}

function test_extract_id_dies_without_an_id() {
  local out=""
  (nv::extract_id out '{}' volume >/dev/null 2>&1)
  assert_exit_code 1
}

function test_require_uint_accepts_digits_and_empty() {
  nv::require_uint 10 limit
  nv::require_uint "" limit
  assert_equals "0" "$?"
}

function test_require_uint_rejects_non_numeric() {
  (nv::require_uint ten limit >/dev/null 2>&1)
  assert_exit_code 2
}

function test_require_id_rejects_path_and_query_metacharacters() {
  local out
  out="$(nv::require_id id 'abc/../../etc' 'instance id' 2>&1)"
  assert_exit_code 2
  assert_contains "invalid instance id" "$out"
}

function test_require_id_accepts_uuid_shapes() {
  local id
  nv::require_id id 'd4e82677-3f80-4020-a731-d15b1c589aa8' 'volume id'
  assert_equals 'd4e82677-3f80-4020-a731-d15b1c589aa8' "$id"
}

function test_table_renders_columns_from_an_array() {
  local out
  out="$(nv::table '[{"id":"a","name":"Alpha"},{"id":"b","name":"Beta"}]' id name)"
  assert_contains "id  name" "$out"
  assert_contains "a   Alpha" "$out"
}
