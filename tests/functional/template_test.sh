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
  source "$RP_ROOT/commands/template.sh"
  eval "$_opts"
}

# Double: METHOD+PATH -> TP_CAPTURE, body -> TP_BODY, answer from TP_STUB_BODY.
function set_up() {
  TP_CAPTURE="$(mktemp)"
  TP_BODY="$(mktemp)"
  # The v2 template create/update answer {"template_id": …}.
  TP_STUB_BODY='{"template_id":"tpl-001"}'
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$TP_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$TP_BODY"
    fi
    printf '%s' "$TP_STUB_BODY"
  }
}

function tear_down() {
  rm -f "$TP_CAPTURE" "$TP_BODY"
}

# The create spec requires name, type AND image — a bare string id no longer
# passes, and the documented create route is no longer a convention guess.
function test_create_posts_name_type_and_image_to_the_documented_route() {
  nv::args_parse --name base --type instance --image img:22.04
  local out
  out="$(_template_create 2>/dev/null)"
  assert_equals "tpl-001" "$out"
  assert_contains "POST /templates" "$(<"$TP_CAPTURE")"
  local body
  body="$(<"$TP_BODY")"
  assert_equals "base" "$(printf '%s' "$body" | jq -r '.name')"
  assert_equals "instance" "$(printf '%s' "$body" | jq -r '.type')"
  assert_equals "img:22.04" "$(printf '%s' "$body" | jq -r '.image')"
}

function test_create_requires_type() {
  nv::args_parse --name base --image img
  (_template_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_requires_name_and_image() {
  nv::args_parse --type instance
  (_template_create >/dev/null 2>&1)
  assert_exit_code 2
}

# Template ports are {port, protocol} objects (instance shape): a bare port
# defaults to tcp, https is rejected.
function test_create_builds_object_ports() {
  nv::args_parse --name base --type instance --image img --port 8080 --port 9000:http
  _template_create >/dev/null 2>&1
  local body
  body="$(<"$TP_BODY")"
  assert_equals '[{"port":8080,"protocol":"tcp"},{"port":9000,"protocol":"http"}]' \
    "$(printf '%s' "$body" | jq -rc '.ports')"
}

function test_create_rejects_https_port_protocol() {
  nv::args_parse --name base --type instance --image img --port 443:https
  (_template_create >/dev/null 2>&1)
  assert_exit_code 2
}

# Builder usage errors must escape the command substitutions (exit 2 from the
# caller's shell), so the env/ports call sites carry the catch pattern.
function test_create_rejects_bad_env_pair() {
  nv::args_parse --name base --type instance --image img --env =v
  (_template_create >/dev/null 2>&1)
  assert_exit_code 2
}

# The update spec takes the create key set with no key required.
function test_update_puts_only_the_set_fields() {
  nv::args_parse tpl-001 --name renamed --image img:23
  _template_update >/dev/null 2>&1
  assert_contains "PUT /templates/tpl-001" "$(<"$TP_CAPTURE")"
  local body
  body="$(<"$TP_BODY")"
  assert_equals "renamed" "$(printf '%s' "$body" | jq -r '.name')"
  assert_equals "img:23" "$(printf '%s' "$body" | jq -r '.image')"
  assert_equals "false" "$(printf '%s' "$body" | jq -r 'has("type")')"
}

function test_update_builds_envs_ports_and_rootfs() {
  nv::args_parse tpl-001 --env A=1 --port 8888 --rootfs-gb 30
  _template_update >/dev/null 2>&1
  local body
  body="$(<"$TP_BODY")"
  assert_equals '[{"key":"A","value":"1"}]' "$(printf '%s' "$body" | jq -rc '.envs')"
  assert_equals '[{"port":8888,"protocol":"tcp"}]' "$(printf '%s' "$body" | jq -rc '.ports')"
  assert_equals "30" "$(printf '%s' "$body" | jq -r '.rootfs_size_gb')"
}

function test_update_exits_usage_with_nothing_to_change() {
  nv::args_parse tpl-001
  (_template_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_update_rejects_non_numeric_rootfs() {
  nv::args_parse tpl-001 --rootfs-gb big
  (_template_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_update_rejects_a_malformed_id() {
  nv::args_parse 'tpl/9' --name x
  (_template_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_delete_sends_the_documented_delete_route() {
  TP_STUB_BODY='{}'
  nv::cmd_template delete tpl-001 >/dev/null 2>&1
  assert_contains "DELETE /templates/tpl-001" "$(<"$TP_CAPTURE")"
}

function test_create_is_idempotent_by_name() {
  nv::http() {
    if [[ "$1" == "GET" ]]; then
      printf '{"data":[{"id":"tpl-9","name":"base"}]}'
    else
      printf '{"template_id":"posted"}'
    fi
  }
  nv::args_parse --name base --type instance --image img
  local out
  out="$(_template_create 2>/dev/null)"
  assert_equals "tpl-9" "$out"
}

function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  nv::cmd_template help >"$tmp" 2>/dev/null
  assert_contains "Usage: nv template" "$(<"$tmp")"
  rm -f "$tmp"
}
