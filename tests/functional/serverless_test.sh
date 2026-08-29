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
# nv::http_async is doubled alongside nv::http_url because both drive curl
# outside the doubled nv::http.
function set_up() {
  SL_CAPTURE="$(mktemp)"
  SL_BODY="$(mktemp)"
  SL_STUB_BODY='{"id":"new-ep"}'
  SL_ASYNC_STUB_BODY='{"id":"job-1","status":"PENDING"}'
  # The invoke seams preflight the key outside the doubled nv::http — provide
  # one so they are reachable.
  export NOVITA_API_KEY="nv-test"
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$SL_BODY"
    fi
    printf '%s' "$SL_STUB_BODY"
  }
  nv::http_async() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$SL_BODY"
    fi
    printf '%s' "$SL_ASYNC_STUB_BODY"
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

function test_create_defaults_type_to_sync_and_sends_worker_config_default() {
  nv::args_parse --name api --product p --image i --app a --region r
  _serverless_create >/dev/null 2>&1
  local body
  body="$(<"$SL_BODY")"
  assert_equals "sync" "$(printf '%s' "$body" | jq -r '.type')"
  assert_equals "1" "$(printf '%s' "$body" | jq -r '.worker_config.max_replicas')"
}

function test_create_rejects_non_numeric_scaling_flags() {
  nv::args_parse --name api --product p --image i --app a --region r --max abc
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_sends_integer_ports() {
  nv::args_parse --name api --product p --image i --app a --region r --port 8080 --port 9000
  _serverless_create >/dev/null 2>&1
  local body
  body="$(<"$SL_BODY")"
  assert_equals '[8080,9000]' "$(printf '%s' "$body" | jq -rc '.ports')"
}

function test_create_rejects_out_of_range_port() {
  nv::args_parse --name api --product p --image i --app a --region r --port 65536
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_rejects_port_protocol_suffix() {
  nv::args_parse --name api --product p --image i --app a --region r --port 8080:tcp
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_accepts_async_type() {
  nv::args_parse --name api --product p --image i --app a --region r --type async
  _serverless_create >/dev/null 2>&1
  local body
  body="$(<"$SL_BODY")"
  assert_equals "async" "$(printf '%s' "$body" | jq -r '.type')"
}

function test_create_rejects_stream_type() {
  nv::args_parse --name api --product p --image i --app a --region r --type stream
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
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

function test_create_rejects_renamed_request_count_policy() {
  nv::args_parse --name api --product p --image i --app a --region r --policy request_count
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_builds_concurrency_policy() {
  nv::args_parse --name api --product p --image i --app a --region r --policy concurrency --policy-value 50
  _serverless_create >/dev/null 2>&1
  local body
  body="$(<"$SL_BODY")"
  assert_equals '{"type":"concurrency","value":50}' "$(printf '%s' "$body" | jq -rc '.policy')"
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

# SYNC surface: a sync endpoint's own url serves the customer's HTTP service
# directly — POST {url}{path}, with NO default path appended.
function test_run_on_a_sync_endpoint_posts_to_the_bare_url() {
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ "$2" == "/endpoints/ep-1" ]]; then
      printf '{"id":"ep-1","type":"sync","url":"https://customer.example/inv"}'
    else
      printf '{"id":"unexpected"}'
    fi
  }
  nv::http_url() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ -n "${3:-}" ]]; then
      printf '%s' "$3" >"$SL_BODY"
    fi
    printf '{"answer":1}'
  }
  nv::args_parse ep-1 --input '{"prompt":"hello"}'
  local out
  out="$(_serverless_run 2>/dev/null)"
  assert_contains "GET /endpoints/ep-1" "$(<"$SL_CAPTURE")"
  assert_contains "POST https://customer.example/inv" "$(<"$SL_CAPTURE")"
  assert_not_contains "/run" "$(<"$SL_CAPTURE")"
  assert_contains '{"prompt":"hello"}' "$(<"$SL_BODY")"
  assert_contains '"answer"' "$out"
}

function test_run_on_a_sync_endpoint_appends_the_path_flag() {
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    printf '{"id":"ep-1","type":"sync","url":"https://customer.example/inv"}'
  }
  nv::http_url() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    printf '{}'
  }
  nv::args_parse ep-1 --path /v1/chat/completions
  _serverless_run >/dev/null 2>&1
  assert_contains "POST https://customer.example/inv/v1/chat/completions" "$(<"$SL_CAPTURE")"
}

# ASYNC surface: jobs go to the SHARED host, never the endpoint's url. The
# path segment is the composed {endpoint_id}-{app_name}.
function test_run_on_an_async_endpoint_submits_to_the_shared_host() {
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$SL_CAPTURE"
    if [[ "$2" == "/endpoints/ep-1" ]]; then
      printf '{"id":"ep-1","type":"async","app_name":"my-app"}'
    else
      printf '{"id":"unexpected"}'
    fi
  }
  nv::args_parse ep-1 --input '{"prompt":"hello"}'
  local out
  out="$(_serverless_run 2>/dev/null)"
  assert_contains "POST /ep-1-my-app/run" "$(<"$SL_CAPTURE")"
  assert_not_contains "customer.example" "$(<"$SL_CAPTURE")"
  assert_contains '{"input":{"prompt":"hello"}}' "$(<"$SL_BODY")"
  assert_contains '"PENDING"' "$out"
}

# A payload that already carries an input key passes through unwrapped
# (mirrors the official SDK's run()).
function test_run_on_an_async_endpoint_keeps_a_pre_wrapped_input() {
  nv::http() { printf '{"id":"ep-1","type":"async","app_name":"my-app"}'; }
  nv::args_parse ep-1 --input '{"input":{"n":1}}'
  _serverless_run >/dev/null 2>&1
  assert_contains '{"input":{"n":1}}' "$(<"$SL_BODY")"
}

function test_run_on_an_async_endpoint_uses_the_bare_id_without_app_name() {
  nv::http() { printf '{"id":"ep-1","type":"async"}'; }
  nv::args_parse ep-1
  _serverless_run >/dev/null 2>&1
  assert_contains "POST /ep-1/run" "$(<"$SL_CAPTURE")"
  assert_contains '{"input":{}}' "$(<"$SL_BODY")"
}

function test_run_reads_the_input_payload_from_a_file() {
  nv::http() { printf '{"id":"ep-1","type":"async","app_name":"a"}'; }
  local f
  f="$(mktemp)"
  printf '{"n":1}' >"$f"
  nv::args_parse ep-1 --input "@$f"
  _serverless_run >/dev/null 2>&1
  assert_contains '{"input":{"n":1}}' "$(<"$SL_BODY")"
  rm -f "$f"
}

function test_run_rejects_path_on_an_async_endpoint() {
  nv::http() { printf '{"id":"ep-1","type":"async","app_name":"a"}'; }
  nv::args_parse ep-1 --path /v1/chat
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 2
}

function test_run_dies_on_a_non_json_async_payload() {
  nv::http() { printf '{"id":"ep-1","type":"async","app_name":"a"}'; }
  nv::args_parse ep-1 --input 'not json'
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 1
}

# --sync and /runsync are gone: no alias shim, the flag dies pointing at the
# two-surface verbs.
function test_run_rejects_the_removed_sync_flag() {
  nv::http() { printf '{"id":"ep-1","type":"sync","url":"https://customer.example/inv"}'; }
  nv::args_parse ep-1 --sync
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 2
}

function test_run_dies_when_a_sync_record_has_no_url() {
  nv::http() { printf '{"id":"ep-1","type":"sync"}'; }
  nv::args_parse ep-1
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 1
}

# Async aux verbs against the shared host.
function test_status_polls_the_shared_host() {
  nv::http() { printf '{"id":"ep-1","type":"async","app_name":"my-app"}'; }
  nv::args_parse ep-1 job-9
  local out
  out="$(_serverless_status 2>/dev/null)"
  assert_contains "GET /ep-1-my-app/status/job-9" "$(<"$SL_CAPTURE")"
  assert_contains '"status"' "$out"
}

function test_cancel_posts_to_the_shared_host_without_a_body() {
  nv::http() { printf '{"id":"ep-1","type":"async","app_name":"my-app"}'; }
  nv::args_parse ep-1 job-9
  _serverless_cancel >/dev/null 2>&1
  assert_contains "POST /ep-1-my-app/cancel/job-9" "$(<"$SL_CAPTURE")"
  assert_equals "" "$(<"$SL_BODY")"
}

function test_health_gets_the_queue_status_route() {
  nv::http() { printf '{"id":"ep-1","type":"async","app_name":"my-app"}'; }
  nv::args_parse ep-1
  _serverless_health >/dev/null 2>&1
  assert_contains "GET /ep-1-my-app/health" "$(<"$SL_CAPTURE")"
}

function test_status_requires_a_job_id() {
  nv::http() { printf '{"id":"ep-1","type":"async"}'; }
  nv::args_parse ep-1
  (_serverless_status >/dev/null 2>&1)
  assert_exit_code 2
}

# The endpoint record's region field is region_id (not region) — the column
# must be named for the field so it actually renders.
function test_list_renders_the_region_id_field() {
  SL_STUB_BODY='{"data":[{"id":"ep-1","name":"api","url":"https://x.example","region_id":"r-1"}]}'
  local out
  out="$(nv::cmd_serverless list 2>/dev/null)"
  assert_contains "r-1" "$out"
  assert_contains "region_id" "$out"
}

function test_main_shell_routing_through_the_public_dispatcher() {
  nv::cmd_serverless list --json >/dev/null 2>&1
  assert_contains "GET /endpoints" "$(<"$SL_CAPTURE")"
}
