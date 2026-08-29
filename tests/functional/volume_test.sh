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
  source "$RP_ROOT/commands/volume.sh"
  eval "$_opts"
}

function set_up() {
  VOL_CAPTURE="$(mktemp)"
  VOL_BODY="$(mktemp)"
  VOL_STUB_BODY='{"data":[]}'
  nv::http_v1() {
    printf '%s %s\n' "$1" "$2" >>"$VOL_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$VOL_BODY"
    fi
    printf '%s' "$VOL_STUB_BODY"
  }
}

function tear_down() {
  rm -f "$VOL_CAPTURE" "$VOL_BODY"
}

# The create body is v1 camelCase; the response is a BARE JSON STRING id.
function test_create_posts_camelcase_body_to_the_create_path() {
  VOL_STUB_BODY='"st-123"'
  nv::args_parse --name myvol --size 100 --cluster 5
  local out
  out="$(_volume_create 2>/dev/null)"
  assert_equals "st-123" "$out"
  assert_contains "POST /networkstorage/create" "$(<"$VOL_CAPTURE")"
  local body
  body="$(<"$VOL_BODY")"
  assert_equals "5" "$(printf '%s' "$body" | jq -r '.clusterId')"
  assert_equals "myvol" "$(printf '%s' "$body" | jq -r '.storageName')"
  assert_equals "100" "$(printf '%s' "$body" | jq -r '.storageSize')"
}

function test_create_requires_name_size_and_cluster() {
  nv::args_parse --name myvol --size 100
  (_volume_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_rejects_non_numeric_size() {
  nv::args_parse --name myvol --size big --cluster 5
  (_volume_create >/dev/null 2>&1)
  assert_exit_code 2
}

# The list verb GETs /networkstorages/list (NOT a POST), with pageNo/pageSize.
function test_list_uses_the_list_route_with_v1_pagination() {
  nv::cmd_volume list --page 1 --limit 20 >/dev/null 2>&1
  assert_contains "GET /networkstorages/list?pageNo=1&pageSize=20" "$(<"$VOL_CAPTURE")"
}

function test_list_forwards_storage_filters() {
  nv::cmd_volume list --name myvol --id st-9 >/dev/null 2>&1
  assert_contains "storageName=myvol" "$(<"$VOL_CAPTURE")"
  assert_contains "storageId=st-9" "$(<"$VOL_CAPTURE")"
}

function test_list_tables_v1_field_names() {
  VOL_STUB_BODY='{"data":[{"storageId":"st-1","storageName":"myvol","storageSize":10,"clusterName":"EU-01"}],"total":1}'
  local out
  out="$(nv::cmd_volume list 2>/dev/null)"
  assert_contains "myvol" "$out"
  assert_contains "st-1" "$out"
}

# Delete/update are bespoke v1 POST verbs (NOT REST DELETE /networkstorages/{id}).
function test_delete_posts_the_storage_id_to_the_delete_route() {
  nv::args_parse st-9
  _volume_delete >/dev/null 2>&1
  assert_contains "POST /networkstorage/delete" "$(<"$VOL_CAPTURE")"
  local body
  body="$(<"$VOL_BODY")"
  assert_equals "st-9" "$(printf '%s' "$body" | jq -r '.storageId')"
}

function test_delete_requires_an_id() {
  nv::args_parse
  (_volume_delete >/dev/null 2>&1)
  assert_exit_code 2
}

function test_delete_rejects_a_malformed_id() {
  nv::args_parse 'st/9'
  (_volume_delete >/dev/null 2>&1)
  assert_exit_code 2
}

function test_update_posts_storage_id_name_and_size() {
  nv::args_parse st-9 --name renamed --size 50
  _volume_update >/dev/null 2>&1
  assert_contains "POST /networkstorage/update" "$(<"$VOL_CAPTURE")"
  local body
  body="$(<"$VOL_BODY")"
  assert_equals "st-9" "$(printf '%s' "$body" | jq -r '.storageId')"
  assert_equals "renamed" "$(printf '%s' "$body" | jq -r '.storageName')"
  assert_equals "50" "$(printf '%s' "$body" | jq -r '.storageSize')"
}

function test_update_sends_only_the_set_fields() {
  nv::args_parse st-9 --size 50
  _volume_update >/dev/null 2>&1
  local body
  body="$(<"$VOL_BODY")"
  assert_equals "false" "$(printf '%s' "$body" | jq -r 'has("storageName")')"
  assert_equals "50" "$(printf '%s' "$body" | jq -r '.storageSize')"
}

function test_update_rejects_non_numeric_size() {
  nv::args_parse st-9 --size big
  (_volume_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_update_exits_usage_with_nothing_to_change() {
  nv::args_parse st-9
  (_volume_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_main_shell_routing_through_the_public_dispatcher() {
  nv::cmd_volume list >/dev/null 2>&1
  assert_contains "GET /networkstorages/list" "$(<"$VOL_CAPTURE")"
}

function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  nv::cmd_volume help >"$tmp" 2>/dev/null
  assert_contains "Usage: nv volume" "$(<"$tmp")"
  rm -f "$tmp"
}
