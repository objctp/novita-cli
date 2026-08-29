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
  source "$RP_ROOT/lib/resource.sh"
  eval "$_opts"
}

# Shared double: capture the namespace-routed call; answer from NV_STUB_BODY.
function _stub_res_http() {
  RES_CAPTURE="$(mktemp)"
  NV_STUB_BODY="${NV_STUB_BODY:-'[]'}"
  nv::res_http() {
    printf '%s %s\n' "$1" "$2" >>"$RES_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >>"$RES_CAPTURE"
    fi
    printf '%s' "$NV_STUB_BODY"
  }
}

function tear_down() {
  [[ -n "${RES_CAPTURE:-}" ]] && rm -f "$RES_CAPTURE"
  RES_CAPTURE=""
}

function test_resource_list_routes_by_descriptor_namespace_and_unwraps_data() {
  _stub_res_http
  NV_STUB_BODY='{"data":[{"id":"a","name":"Alpha"}],"next_cursor":"","has_more":false}'
  local out
  out="$(nv::resource_list pod id name)"
  assert_contains "GET /instances" "$(<"$RES_CAPTURE")"
  assert_contains "Alpha" "$out"
}

function test_resource_list_forwards_v2_pagination_params() {
  _stub_res_http
  NV_STUB_BODY='{"data":[]}'
  nv::args_parse --limit 5 --cursor c-9
  nv::resource_list pod id >/dev/null 2>&1
  assert_contains "GET /instances?limit=5&cursor=c-9" "$(<"$RES_CAPTURE")"
}

function test_resource_list_forwards_v1_pagination_params() {
  _stub_res_http
  NV_STUB_BODY='{"data":[]}'
  nv::args_parse --page 2 --limit 10
  nv::resource_list volume storageId storageName >/dev/null 2>&1
  assert_contains "GET /networkstorages/list?pageNo=2&pageSize=10" "$(<"$RES_CAPTURE")"
}

function test_resource_list_passes_json_through() {
  _stub_res_http
  NV_STUB_BODY='{"data":[{"id":"a"}]}'
  nv::args_parse --json
  local out
  out="$(nv::resource_list pod id)"
  assert_equals '[{"id":"a"}]' "$out"
}

function test_resource_get_fetches_by_id() {
  _stub_res_http
  NV_STUB_BODY='{"id":"a","name":"Alpha"}'
  nv::args_parse a
  local out
  out="$(nv::resource_get pod)"
  assert_contains "GET /instances/a" "$(<"$RES_CAPTURE")"
  assert_contains '"Alpha"' "$out"
}

function test_resource_get_rejects_crafted_ids() {
  nv::args_parse '../etc/passwd'
  (nv::resource_get pod >/dev/null 2>&1)
  assert_exit_code 2
}

function test_resource_delete_sends_delete_by_id() {
  _stub_res_http
  NV_STUB_BODY=''
  nv::args_parse a
  local out
  out="$(nv::resource_delete pod 2>&1)"
  assert_contains "DELETE /instances/a" "$(<"$RES_CAPTURE")"
  assert_contains "deleted pod a" "$out"
}

function test_resource_create_posts_body_and_extracts_object_id() {
  _stub_res_http
  NV_STUB_BODY='{"id":"new-1"}'
  nv::args_parse
  local out
  out="$(nv::resource_create pod '' '{"name":"x"}' 2>/dev/null)"
  assert_equals "new-1" "$out"
  assert_contains "POST /instances" "$(<"$RES_CAPTURE")"
  assert_contains '{"name":"x"}' "$(<"$RES_CAPTURE")"
}

# v1 storage create answers a bare JSON string; the shared verb must unwrap it.
function test_resource_create_extracts_bare_string_id() {
  _stub_res_http
  NV_STUB_BODY='"st-123"'
  nv::args_parse
  local out
  out="$(nv::resource_create volume '' '{}' 2>/dev/null)"
  assert_equals "st-123" "$out"
  # The create goes to the descriptor's create-path override, not the list path.
  assert_contains "POST /networkstorage/create" "$(<"$RES_CAPTURE")"
}

function test_resource_create_is_idempotent_by_name() {
  _stub_res_http
  NV_STUB_BODY='{"data":[{"id":"exist-1","name":"dup"}]}'
  nv::args_parse
  local out
  out="$(nv::resource_create pod dup '{"name":"dup"}' 2>/dev/null)"
  assert_equals "exist-1" "$out"
  assert_not_contains "POST" "$(<"$RES_CAPTURE")"
}

function test_resource_create_forces_past_the_name_gate() {
  # Method-aware double: the gate's GET sees the duplicate, the POST creates.
  RES_CAPTURE="$(mktemp)"
  nv::res_http() {
    printf '%s %s\n' "$1" "$2" >>"$RES_CAPTURE"
    if [[ "$1" == "GET" ]]; then
      printf '{"data":[{"id":"exist-1","name":"dup"}]}'
    else
      printf '{"id":"new-1"}'
    fi
  }
  nv::args_parse --force
  local out
  out="$(nv::resource_create pod dup '{"name":"dup"}' 2>/dev/null)"
  assert_equals "new-1" "$out"
  assert_contains "POST" "$(<"$RES_CAPTURE")"
}

function test_resource_id_resolves_a_name_to_an_id() {
  _stub_res_http
  NV_STUB_BODY='{"data":[{"id":"a","name":"Alpha"},{"id":"b","name":"Beta"}]}'
  nv::args_parse
  local out
  out="$(nv::resource_id pod Alpha)"
  assert_equals "a" "$out"
}

function test_resource_id_supports_v1_field_names() {
  _stub_res_http
  NV_STUB_BODY='{"data":[{"storageId":"st-1","storageName":"myvol"}]}'
  nv::args_parse
  local out
  out="$(nv::resource_id volume myvol storageId storageName)"
  assert_equals "st-1" "$out"
}
