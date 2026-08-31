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
  source "$RP_ROOT/commands/account.sh"
  eval "$_opts"
}

function set_up() {
  ACCT_CAPTURE="$(mktemp)"
  ACCT_STUB_BODY='{"availableBalance":"1000000","cashBalance":"800000","creditLimit":"200000","pendingCharges":"0","outstandingInvoices":"0"}'
  nv::http_basic() {
    printf '%s %s\n' "$1" "$2" >>"$ACCT_CAPTURE"
    printf '%s' "$ACCT_STUB_BODY"
  }
}

function tear_down() {
  rm -f "$ACCT_CAPTURE"
  unset -f nv::http_basic
}

function test_balance_gets_the_bare_detail_route() {
  nv::cmd_account balance >/dev/null 2>&1
  assert_equals "GET /billing/balance/detail" "$(<"$ACCT_CAPTURE")"
}

function test_balance_is_implied_when_no_verb_is_given() {
  nv::cmd_account >/dev/null 2>&1
  assert_equals "GET /billing/balance/detail" "$(<"$ACCT_CAPTURE")"
}

function test_flags_after_the_resource_reach_the_parser_not_the_verb_slot() {
  nv::cmd_account --json >/dev/null 2>&1
  assert_equals "GET /billing/balance/detail" "$(<"$ACCT_CAPTURE")"
}

# The response is a BARE object (no `data` wrapper); the human view is a
# key:value table over the raw 1/10000-USD strings.
function test_balance_tables_the_raw_fields_key_value() {
  local out
  out="$(nv::cmd_account balance 2>/dev/null)"
  assert_contains "availableBalance" "$out"
  assert_contains "1000000" "$out"
  assert_contains "outstandingInvoices" "$out"
}

function test_balance_json_prints_the_raw_body() {
  local out
  out="$(nv::cmd_account balance --json 2>/dev/null)"
  assert_equals "$ACCT_STUB_BODY" "$out"
}

function test_balance_jq_prints_the_selected_value() {
  local out
  out="$(nv::cmd_account balance --jq .availableBalance 2>/dev/null)"
  assert_equals "1000000" "$out"
}

function test_should_reject_an_unknown_verb() {
  (nv::cmd_account frobnicate >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  nv::cmd_account help >"$tmp" 2>/dev/null
  assert_contains "Usage: nv account" "$(<"$tmp")"
  rm -f "$tmp"
}
