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
  source "$RP_ROOT/commands/pod.sh"
  eval "$_opts"
}

# Double: the METHOD+PATH land in POD_CAPTURE, the request BODY (if any) in
# POD_BODY, and the stub answer comes from POD_STUB_BODY.
function set_up() {
  POD_CAPTURE="$(mktemp)"
  POD_BODY="$(mktemp)"
  POD_STUB_BODY='{"id":"new-1"}'
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$POD_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$POD_BODY"
    fi
    printf '%s' "$POD_STUB_BODY"
  }
}

function tear_down() {
  rm -f "$POD_CAPTURE" "$POD_BODY"
}

function test_create_posts_the_confirmed_v2_body_shape() {
  nv::args_parse --name dev --product prod-1 --image nginx --gpu-count 2 --rootfs-gb 30
  local out
  out="$(_pod_create 2>/dev/null)"
  assert_equals "new-1" "$out"
  assert_contains "POST /instances" "$(<"$POD_CAPTURE")"
  local body
  body="$(<"$POD_BODY")"
  assert_equals "prod-1" "$(printf '%s' "$body" | jq -r '.product_id')"
  assert_equals "nginx" "$(printf '%s' "$body" | jq -r '.image')"
  assert_equals "2" "$(printf '%s' "$body" | jq -r '.resource.gpu_num')"
  assert_equals "30" "$(printf '%s' "$body" | jq -r '.resource.rootfs_size_gb')"
}

function test_create_sends_resource_defaults_when_size_flags_unset() {
  nv::args_parse --product prod-1 --image nginx
  _pod_create >/dev/null 2>&1
  local body
  body="$(<"$POD_BODY")"
  assert_equals "1" "$(printf '%s' "$body" | jq -r '.resource.gpu_num')"
  assert_equals "20" "$(printf '%s' "$body" | jq -r '.resource.rootfs_size_gb')"
}

function test_create_omits_unset_optional_strings() {
  nv::args_parse --product prod-1 --image nginx
  _pod_create >/dev/null 2>&1
  local body
  body="$(<"$POD_BODY")"
  assert_equals "false" "$(printf '%s' "$body" | jq -r 'has("name")')"
  assert_equals "false" "$(printf '%s' "$body" | jq -r 'has("entrypoint")')"
}

function test_create_builds_envs_ports_volumes_and_regions() {
  nv::args_parse --product p --image i \
    --env A=1 --env B=2 \
    --port 8080:tcp --port 9000 \
    --volume st-1:/data --volume st-2:/workspace \
    --region r-1,r-2
  _pod_create >/dev/null 2>&1
  local body
  body="$(<"$POD_BODY")"
  assert_equals '2' "$(printf '%s' "$body" | jq -r '.envs | length')"
  assert_equals '[{"port":8080,"protocol":"tcp"},{"port":9000,"protocol":"tcp"}]' \
    "$(printf '%s' "$body" | jq -rc '.ports')"
  assert_equals '/workspace' "$(printf '%s' "$body" | jq -r '.volumes[1].mount_point')"
  assert_equals '["r-1","r-2"]' "$(printf '%s' "$body" | jq -rc '.candidate_regions')"
}

function test_create_rejects_https_port_protocol() {
  nv::args_parse --product p --image i --port 443:https
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_embeds_jupyter_tools_when_flagged() {
  nv::args_parse --product p --image i --jupyter --jupyter-port 9999
  _pod_create >/dev/null 2>&1
  local body
  body="$(<"$POD_BODY")"
  assert_equals "9999" "$(printf '%s' "$body" | jq -r '.tools.jupyter.port')"
}

function test_create_requires_product_and_image() {
  nv::args_parse --product prod-1
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_sends_postpaid_billing_by_default() {
  nv::args_parse --product prod-1 --image nginx
  _pod_create >/dev/null 2>&1
  local body
  body="$(<"$POD_BODY")"
  assert_equals "postpaid" "$(printf '%s' "$body" | jq -r '.billing.mode')"
}

function test_create_honours_billing_mode_flag() {
  nv::args_parse --product prod-1 --image nginx --billing-mode prepaid
  _pod_create >/dev/null 2>&1
  local body
  body="$(<"$POD_BODY")"
  assert_equals "prepaid" "$(printf '%s' "$body" | jq -r '.billing.mode')"
}

function test_create_rejects_unknown_billing_mode() {
  nv::args_parse --product prod-1 --image nginx --billing-mode barter
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_is_idempotent_by_name() {
  local posted
  posted="$(mktemp)"
  nv::http() {
    if [[ "$1" == "GET" ]]; then
      printf '{"data":[{"id":"abc","name":"dup"}]}'
    else
      printf 'POSTED' >"$posted"
      printf '{"id":"abc"}'
    fi
  }
  nv::args_parse --name dup --product p --image i
  local out
  out="$(_pod_create 2>/dev/null)"
  assert_equals "abc" "$out"
  assert_equals "" "$(cat "$posted")"
  rm -f "$posted"
}

function test_start_and_stop_put_their_routes() {
  nv::args_parse inst-1
  _pod_lifecycle start >/dev/null 2>&1
  assert_contains "PUT /instances/inst-1/start" "$(<"$POD_CAPTURE")"
  _pod_lifecycle stop >/dev/null 2>&1
  assert_contains "PUT /instances/inst-1/stop" "$(<"$POD_CAPTURE")"
}

# The v2 instance record carries status as an OBJECT {status, error, message};
# the table must render the inner status, one line per pod (error/message stay
# reachable via --json/--jq).
function test_list_renders_the_nested_status_field() {
  POD_STUB_BODY='{"data":[{"id":"i-1","name":"dev","status":{"status":"running","error":null,"message":null},"region":"r-1"}]}'
  local out
  out="$(nv::cmd_pod list 2>/dev/null)"
  assert_contains "running" "$out"
  assert_not_contains '"message"' "$out"
}

function test_main_shell_routing_through_the_public_dispatcher() {
  nv::cmd_pod list --json >/dev/null 2>&1
  assert_contains "GET /instances" "$(<"$POD_CAPTURE")"
}

function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  nv::cmd_pod help >"$tmp" 2>/dev/null
  assert_contains "Usage: nv pod" "$(<"$tmp")"
  rm -f "$tmp"
}
