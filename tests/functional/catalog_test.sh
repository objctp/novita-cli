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
  source "$RP_ROOT/commands/catalog.sh"
  eval "$_opts"
}

function set_up() {
  CAT_CAPTURE="$(mktemp)"
  CAT_STUB_BODY='{"data":[],"next_cursor":"","has_more":false}'
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$CAT_CAPTURE"
    printf '%s' "$CAT_STUB_BODY"
  }
}

function tear_down() {
  rm -f "$CAT_CAPTURE"
}

# The products endpoint requires BOTH query params or the API answers 400.
function test_gpu_pins_type_and_category() {
  nv::cmd_catalog gpu >/dev/null 2>&1
  assert_contains "GET /products?type=gpu&category=instance" "$(<"$CAT_CAPTURE")"
}

function test_serverless_pins_the_serverless_category() {
  nv::cmd_catalog serverless >/dev/null 2>&1
  assert_contains "GET /products?type=gpu&category=serverless" "$(<"$CAT_CAPTURE")"
}

function test_products_forward_limit_and_cursor() {
  nv::cmd_catalog gpu --limit 3 --cursor c-7 >/dev/null 2>&1
  assert_contains "limit=3&cursor=c-7" "$(<"$CAT_CAPTURE")"
}

function test_products_filter_applies_jq() {
  local out
  CAT_STUB_BODY='{"data":[{"id":"p1","name":"RTX 4090"},{"id":"p2","name":"L4"}]}'
  out="$(nv::cmd_catalog gpu --json --jq 'map(.id)' 2>/dev/null)"
  assert_equals '["p1","p2"]' "$out"
}

function test_regions_fetch_the_regions_path() {
  nv::cmd_catalog regions >/dev/null 2>&1
  assert_contains "GET /regions" "$(<"$CAT_CAPTURE")"
}

function test_table_renders_product_rows() {
  CAT_STUB_BODY='{"data":[{"id":"p1","name":"RTX 4090"}]}'
  local out
  out="$(nv::cmd_catalog gpu 2>/dev/null)"
  assert_contains "RTX 4090" "$out"
}
