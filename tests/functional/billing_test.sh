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
  source "$RP_ROOT/commands/billing.sh"
  eval "$_opts"
}

function set_up() {
  BILL_CAPTURE="$(mktemp)"
  BILL_STUB_BODY='{"data":[]}'
  nv::http_basic() {
    printf '%s %s\n' "$1" "$2" >>"$BILL_CAPTURE"
    printf '%s' "$BILL_STUB_BODY"
  }
}

function tear_down() {
  rm -f "$BILL_CAPTURE"
  unset -f nv::http_basic
}

# Monthly bill: this endpoint paginates with `page` (NOT pageNo like the v1
# storage list) and takes a YYYY-MM `startMonth`, not a timestamp.
function test_monthly_gets_the_monthly_route_with_page_pagination() {
  nv::cmd_billing monthly --month 2025-12 --page 2 --limit 50 >/dev/null 2>&1
  assert_contains "GET /billing/monthly/bill?startMonth=2025-12&page=2&pageSize=50" "$(<"$BILL_CAPTURE")"
}

function test_monthly_omits_unset_params_entirely() {
  nv::cmd_billing monthly >/dev/null 2>&1
  assert_equals "GET /billing/monthly/bill" "$(<"$BILL_CAPTURE")"
}

function test_monthly_rejects_a_bad_month_format() {
  nv::args_parse --month 2025-13
  (_billing_monthly >/dev/null 2>&1)
  assert_exit_code 2
  nv::args_parse --month december
  (_billing_monthly >/dev/null 2>&1)
  assert_exit_code 2
}

function test_monthly_rejects_non_numeric_page() {
  nv::args_parse --page big
  (_billing_monthly >/dev/null 2>&1)
  assert_exit_code 2
}

function test_monthly_unwraps_data_and_tables_the_bill_fields() {
  BILL_STUB_BODY='{"data":[{"billId":"b1","billingMonth":"2025-12","totalAmount":"1000000","status":"paid"}]}'
  local out
  out="$(nv::cmd_billing monthly 2>/dev/null)"
  assert_contains "2025-12" "$out"
  assert_contains "paid" "$out"
}

function test_usage_requires_cycle_and_product_category() {
  nv::args_parse
  (_billing_usage >/dev/null 2>&1)
  assert_exit_code 2
  nv::args_parse --cycle Day
  (_billing_usage >/dev/null 2>&1)
  assert_exit_code 2
}

function test_usage_rejects_an_unknown_cycle() {
  nv::args_parse --cycle daily --product-category llm
  (_billing_usage >/dev/null 2>&1)
  assert_exit_code 2
}

function test_usage_sends_cycle_category_and_window() {
  nv::args_parse --cycle Day --product-category llm --start 1764547200 --end 1767225599
  _billing_usage >/dev/null 2>&1
  assert_contains "GET /billing/bill/list?cycleType=Day&productCategory=llm&startTime=1764547200&endTime=1767225599" "$(<"$BILL_CAPTURE")"
}

function test_usage_forwards_optional_product_and_owner_filters() {
  nv::args_parse --cycle Hour --product-category gpu --product H100 --owner inst-9
  _billing_usage >/dev/null 2>&1
  assert_contains "productCategory=gpu" "$(<"$BILL_CAPTURE")"
  assert_contains "productName=H100" "$(<"$BILL_CAPTURE")"
  assert_contains "ownerId=inst-9" "$(<"$BILL_CAPTURE")"
}

# The three bill lists wrap in `bills`, not `data`.
function test_usage_unwraps_the_bills_key() {
  BILL_STUB_BODY='{"bills":[{"productName":"RTX 4090","category":"gpu","payAmount":"10000"}]}'
  local out
  out="$(nv::cmd_billing usage --cycle Day --product-category gpu 2>/dev/null)"
  assert_contains "RTX 4090" "$out"
}

function test_usage_json_prints_the_unwrapped_array() {
  BILL_STUB_BODY='{"bills":[{"productName":"RTX 4090"}]}'
  local out
  out="$(nv::cmd_billing usage --cycle Day --product-category gpu --json 2>/dev/null)"
  assert_equals '[{"productName":"RTX 4090"}]' "$out"
}

function test_fixed_term_gets_the_monthly_list_route() {
  nv::args_parse --category gpu --start 1764547200 --end 1767225599
  _billing_fixed_term >/dev/null 2>&1
  assert_contains "GET /billing/bill/monthly/list?category=gpu&startTime=1764547200&endTime=1767225599" "$(<"$BILL_CAPTURE")"
}

function test_fixed_term_tables_the_cycle_field() {
  BILL_STUB_BODY='{"bills":[{"productName":"A100","tradeType":"monthly_new_buy","cycle":"2025-12","payAmount":"1000000"}]}'
  local out
  out="$(nv::cmd_billing fixed-term 2>/dev/null)"
  assert_contains "monthly_new_buy" "$out"
  assert_contains "2025-12" "$out"
}

function test_apikey_requires_cycle_start_and_end() {
  nv::args_parse --cycle Day
  (_billing_apikey >/dev/null 2>&1)
  assert_exit_code 2
  nv::args_parse --cycle Day --start 1767225600
  (_billing_apikey >/dev/null 2>&1)
  assert_exit_code 2
}

function test_apikey_sends_the_required_window() {
  nv::args_parse --cycle Hour --start 1767225600 --end 1767311999
  _billing_apikey >/dev/null 2>&1
  assert_contains "GET /billing/apikey/bill/list?cycleType=Hour&startTime=1767225600&endTime=1767311999" "$(<"$BILL_CAPTURE")"
}

function test_apikey_tables_the_masked_key_fields() {
  BILL_STUB_BODY='{"bills":[{"apikeyName":"ci-key","apikeyMask":"sk-****","payAmount":"500"}]}'
  local out
  out="$(nv::cmd_billing apikey --cycle Day --start 1767225600 --end 1767311999 2>/dev/null)"
  assert_contains "ci-key" "$out"
  assert_contains "sk-****" "$out"
}

# Transactions REQUIRE pageNo/pageSize, so the bare verb defaults them.
function test_transactions_defaults_the_required_pagination() {
  nv::cmd_billing transactions >/dev/null 2>&1
  assert_contains "GET /bill/transaction?pageNo=1&pageSize=20" "$(<"$BILL_CAPTURE")"
}

function test_transactions_forwards_pagination_and_filters() {
  nv::cmd_billing transactions --page 3 --limit 50 --type recharge \
    --start 1764547200 --end 1767225599 >/dev/null 2>&1
  assert_contains "pageNo=3&pageSize=50" "$(<"$BILL_CAPTURE")"
  assert_contains "transactionType=recharge" "$(<"$BILL_CAPTURE")"
  assert_contains "transactionTimeStart=1764547200" "$(<"$BILL_CAPTURE")"
  assert_contains "transactionTimeEnd=1767225599" "$(<"$BILL_CAPTURE")"
}

function test_transactions_rejects_non_numeric_page() {
  nv::args_parse --page big
  (_billing_transactions >/dev/null 2>&1)
  assert_exit_code 2
}

function test_main_shell_routing_through_the_public_dispatcher() {
  nv::cmd_billing fixed-term >/dev/null 2>&1
  assert_contains "GET /billing/bill/monthly/list" "$(<"$BILL_CAPTURE")"
}

function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  nv::cmd_billing help >"$tmp" 2>/dev/null
  assert_contains "Usage: nv billing" "$(<"$tmp")"
  rm -f "$tmp"
}
