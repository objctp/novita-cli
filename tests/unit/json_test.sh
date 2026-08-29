#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  eval "$_opts"
}

function test_json_str_encodes_a_string() {
  assert_equals '"hi there"' "$(nv::json_str "hi there")"
}

function test_json_obj_builds_from_preencoded_pairs() {
  assert_equals '{"a":1,"b":"x"}' "$(nv::json_obj a 1 b '"x"')"
}

function test_obj_set_skips_empty_values() {
  local obj='{}'
  nv::obj_set obj a 1
  nv::obj_set obj b ""
  assert_equals '{"a":1}' "$obj"
}

function test_envs_to_jsonarray_builds_key_value_objects() {
  assert_equals '[{"key":"A","value":"1"},{"key":"B","value":"2"}]' \
    "$(nv::envs_to_jsonarray $'A=1\nB=2')"
}

function test_envs_to_jsonarray_splits_on_first_equals() {
  assert_equals '[{"key":"LIST","value":"a,b"}]' \
    "$(nv::envs_to_jsonarray 'LIST=a,b')"
}

function test_envs_to_jsonarray_rejects_missing_key() {
  (nv::envs_to_jsonarray '=value' >/dev/null 2>&1)
  assert_exit_code 2
}

function test_ports_to_jsonarray_keeps_bare_ports_bare() {
  assert_equals '[8080,9000]' "$(nv::ports_to_jsonarray $'8080\n9000')"
}

function test_ports_to_jsonarray_builds_protocol_objects() {
  assert_equals '[{"port":8080,"protocol":"tcp"},{"port":443,"protocol":"https"}]' \
    "$(nv::ports_to_jsonarray $'8080:tcp\n443:https')"
}

function test_ports_to_jsonarray_rejects_bad_protocol() {
  (nv::ports_to_jsonarray '8080:grpc' >/dev/null 2>&1)
  assert_exit_code 2
}

function test_ports_to_jsonarray_rejects_non_numeric_port() {
  (nv::ports_to_jsonarray 'http' >/dev/null 2>&1)
  assert_exit_code 2
}

function test_ports_obj_defaults_bare_ports_to_tcp() {
  assert_equals '[{"port":8080,"protocol":"tcp"},{"port":9000,"protocol":"tcp"}]' \
    "$(nv::ports_obj_to_jsonarray $'8080\n9000')"
}

function test_ports_obj_keeps_explicit_tcp_and_http() {
  assert_equals '[{"port":8080,"protocol":"tcp"},{"port":9000,"protocol":"http"}]' \
    "$(nv::ports_obj_to_jsonarray $'8080:tcp\n9000:http')"
}

function test_ports_obj_rejects_https_protocol() {
  (nv::ports_obj_to_jsonarray '443:https' >/dev/null 2>&1)
  assert_exit_code 2
}

function test_ports_obj_rejects_bad_protocol() {
  (nv::ports_obj_to_jsonarray '8080:grpc' >/dev/null 2>&1)
  assert_exit_code 2
}

function test_ports_obj_rejects_non_numeric_port() {
  (nv::ports_obj_to_jsonarray 'http' >/dev/null 2>&1)
  assert_exit_code 2
}

function test_volume_mounts_default_to_data_mount_point() {
  assert_equals '[{"type":"network","id":"st1","mount_point":"/data"}]' \
    "$(nv::volume_mounts_to_jsonarray 'st1')"
}

function test_volume_mounts_honour_explicit_mount_point() {
  assert_equals '[{"type":"network","id":"st1","mount_point":"/workspace"}]' \
    "$(nv::volume_mounts_to_jsonarray 'st1:/workspace')"
}

function test_worker_config_omits_unset_fields() {
  assert_equals '{"min_replicas":0,"max_replicas":1}' \
    "$(nv::json_worker_config 0 1 '' '' '' '' '')"
}

function test_worker_config_sets_every_field() {
  assert_equals '{"min_replicas":0,"max_replicas":2,"idle_timeout":300,"max_concurrent_per_worker":10,"gpu_num":1,"rootfs_size_gb":20,"request_timeout":60}' \
    "$(nv::json_worker_config 0 2 300 10 1 20 60)"
}

function test_health_check_sets_both_fields() {
  assert_equals '{"path":"/healthz","port":8080}' "$(nv::json_health_check /healthz 8080)"
}

function test_health_check_allows_partial() {
  assert_equals '{"port":8080}' "$(nv::json_health_check '' 8080)"
}

function test_policy_builds_queue_arm() {
  assert_equals '{"type":"queue","value":100}' "$(nv::json_policy queue 100)"
}

function test_policy_rejects_unknown_type() {
  (nv::json_policy latency 100 >/dev/null 2>&1)
  assert_exit_code 2
}
