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
  source "$RP_ROOT/commands/serverless.sh"
  eval "$_opts"
}

# Double: METHOD+PATH -> SL_CAPTURE, body -> SL_BODY, answer from SL_STUB_BODY.
function set_up() {
  SL_CAPTURE="$(mktemp)"
  SL_BODY="$(mktemp)"
  SL_STUB_BODY='{"id":"new-ep"}'
  # The run verb goes through nv::http_url, which preflights the key outside
  # the doubled nv::http — provide one so the invoke seam is reachable.
  export NOVITA_API_KEY="nv-test"
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$SL_BODY"
    fi
    printf '%s' "$SL_STUB_BODY"
  }
}

function tear_down() {
  rm -f "$SL_CAPTURE" "$SL_BODY"
}

function test_create_posts_the_confirmed_v2_endpoint_shape() {
  nv::args_parse --name api --product prod-1 --image img --app my-app --region r-1 \
    --type sync --min 0 --max 2 --idle 300 --concurrent 10 --gpu-count 1 \
    --rootfs-gb 20 --request-timeout 60 \
    --policy queue --policy-value 100 \
    --health-path /healthz --health-port 8080
  local out
  out="$(_serverless_create 2>/dev/null)"
  assert_equals "new-ep" "$out"
  assert_contains "POST /endpoints" "$(<"$SL_CAPTURE")"
  local body
  body="$(<"$SL_BODY")"
  assert_equals "sync" "$(printf '%s' "$body" | jq -r '.type')"
  assert_equals "my-app" "$(printf '%s' "$body" | jq -r '.app_name')"
  assert_equals "r-1" "$(printf '%s' "$body" | jq -r '.region_id')"
  assert_equals "0" "$(printf '%s' "$body" | jq -r '.worker_config.min_replicas')"
  assert_equals "300" "$(printf '%s' "$body" | jq -r '.worker_config.idle_timeout')"
  assert_equals "queue" "$(printf '%s' "$body" | jq -r '.policy.type')"
  assert_equals "100" "$(printf '%s' "$body" | jq -r '.policy.value')"
  assert_equals "/healthz" "$(printf '%s' "$body" | jq -r '.health_check.path')"
  assert_equals "8080" "$(printf '%s' "$body" | jq -r '.health_check.port')"
}

function test_create_defaults_type_to_sync_and_omits_empty_worker_config() {
  nv::args_parse --name api --product p --image i --app a --region r
  _serverless_create >/dev/null 2>&1
  local body
  body="$(<"$SL_BODY")"
  assert_equals "sync" "$(printf '%s' "$body" | jq -r '.type')"
  assert_equals "false" "$(printf '%s' "$body" | jq -r 'has("worker_config")')"
}

function test_create_rejects_unknown_type() {
  nv::args_parse --name api --product p --image i --app a --region r --type grpc
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_rejects_unknown_policy_type() {
  nv::args_parse --name api --product p --image i --app a --region r --policy latency
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_is_idempotent_by_name_before_flag_validation() {
  nv::http() {
    if [[ "$1" == "GET" ]]; then
      printf '{"data":[{"id":"ep-1","name":"api"}]}'
    else
      printf '{"id":"posted"}'
    fi
  }
  nv::args_parse --name api
  local out
  out="$(_serverless_create 2>/dev/null)"
  assert_equals "ep-1" "$out"
}

function test_update_patches_worker_config_fields() {
  nv::args_parse ep-1 --min 1 --max 3
  _serverless_update >/dev/null 2>&1
  assert_contains "PATCH /endpoints/ep-1" "$(<"$SL_CAPTURE")"
  local body
  body="$(<"$SL_BODY")"
  assert_equals "1" "$(printf '%s' "$body" | jq -r '.worker_config.min_replicas')"
  assert_equals "3" "$(printf '%s' "$body" | jq -r '.worker_config.max_replicas')"
}

function test_update_exits_usage_with_nothing_to_change() {
  nv::args_parse ep-1
  (_serverless_update >/dev/null 2>&1)
  assert_exit_code 2
}

# The run verb must resolve the endpoint's OWN url field and invoke there.
# nv::http_url is doubled too (it drives curl directly, outside nv::http).
function test_run_posts_to_the_endpoint_url_run() {
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ "$2" == "/endpoints/ep-1" ]]; then
      printf '{"id":"ep-1","url":"https://customer.example/inv"}'
    else
      printf '{"id":"unexpected"}'
    fi
  }
  nv::http_url() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$SL_BODY"
    fi
    printf '{"id":"job-1"}'
  }
  nv::args_parse ep-1 --input '{"prompt":"hello"}'
  local out
  out="$(_serverless_run 2>/dev/null)"
  assert_contains "GET /endpoints/ep-1" "$(<"$SL_CAPTURE")"
  assert_contains "POST https://customer.example/inv/run" "$(<"$SL_CAPTURE")"
  assert_contains '{"prompt":"hello"}' "$(<"$SL_BODY")"
  assert_contains '"job-1"' "$out"
}

function test_run_sync_posts_runsync() {
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ "$2" == "/endpoints/ep-1" ]]; then
      printf '{"id":"ep-1","url":"https://customer.example/inv"}'
    else
      printf '{"id":"job-1"}'
    fi
  }
  nv::http_url() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$SL_BODY"
    fi
    printf '{"id":"job-2"}'
  }
  local f
  f="$(mktemp)"
  printf '{"n":1}' >"$f"
  nv::args_parse ep-1 --sync --input "@$f"
  _serverless_run >/dev/null 2>&1
  assert_contains "POST https://customer.example/inv/runsync" "$(<"$SL_CAPTURE")"
  assert_contains '{"n":1}' "$(<"$SL_BODY")"
  rm -f "$f"
}

function test_run_dies_when_the_record_has_no_url() {
  nv::http() { printf '{"id":"ep-1"}'; }
  nv::args_parse ep-1
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 1
}

function test_main_shell_routing_through_the_public_dispatcher() {
  nv::cmd_serverless list --json >/dev/null 2>&1
  assert_contains "GET /endpoints" "$(<"$SL_CAPTURE")"
}
