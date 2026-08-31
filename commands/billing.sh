#!/usr/bin/env bash
#
# Query Novita bills: monthly, usage, fixed-term, and more.
#
# Five read-only GETs in the basic namespace (/openapi/v1). All money fields
# are strings in 1/10000 USD ("10000" = $1.00); windows are Unix-seconds
# timestamps except the monthly bill, which anchors on a YYYY-MM month. The
# endpoints disagree on envelope and pagination — monthly/transactions wrap in
# `data`, the three bill lists in `bills`, and only monthly (`page`) and
# transactions (`pageNo`, required) paginate — so each verb pins its own query
# params.
#
# Usage: nv billing <verb> [flags]
#

# Unwrap the named envelope key, apply --jq when given, then --json or table.
# Shared by all five verbs, which differ only in key and columns.
_billing_emit() {
  local key="$1" body="$2"
  shift 2
  local arr
  arr="$(nv::unwrap "$key" "$body")"
  local jqf
  jqf="$(nv::args_get jq)"
  [[ -z "$jqf" ]] || arr="$(printf '%s' "$arr" | jq -c "$jqf")" || nv::die "invalid --jq filter: $jqf"
  nv::emit_json_or "$arr" nv::table "$arr" "$@"
}

# Assign the validated --cycle value to the nameref in $1, else exit with $2's
# usage line. Must run in the caller's shell (never inside $()) so the usage
# exit fires — same rule as nv::require_pos.
_billing_require_cycle() {
  local -n c_out="$1"
  local usage="$2"
  c_out="$(nv::args_get cycle)"
  case "$c_out" in
  Hour | Day | Week | Month) ;;
  *) nv::usage "$usage" ;;
  esac
}

_billing_monthly() {
  local month page limit
  month="$(nv::args_get month)"
  [[ -z "$month" || "$month" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] ||
    nv::usage "usage: nv billing monthly [--month YYYY-MM] [--page N] [--limit N] [--json] [--jq <f>] (invalid --month '$month')"
  page="$(nv::args_get_uint page)" || exit 2
  limit="$(nv::args_get_uint limit)" || exit 2
  # This endpoint paginates with `page` (not pageNo) and answers no total.
  local body
  body="$(nv::http_basic GET "/billing/monthly/bill$(nv::query_params \
    startMonth "$month" \
    page "$page" \
    pageSize "$limit")")"
  _billing_emit data "$body" billId billingMonth totalAmount status
}

_billing_usage() {
  local usage="usage: nv billing usage --cycle Hour|Day|Week|Month --product-category <c>
              [--product <n>] [--category <c>] [--start <ts>] [--end <ts>] [--owner <id>]"
  local cycle pc start end
  _billing_require_cycle cycle "$usage"
  pc="$(nv::args_get product-category)"
  [[ -n "$pc" ]] || nv::usage "$usage"
  start="$(nv::args_get_uint start)" || exit 2
  end="$(nv::args_get_uint end)" || exit 2
  local body
  body="$(nv::http_basic GET "/billing/bill/list$(nv::query_params \
    cycleType "$cycle" \
    productCategory "$pc" \
    productName "$(nv::args_get product)" \
    category "$(nv::args_get category)" \
    startTime "$start" \
    endTime "$end" \
    ownerId "$(nv::args_get owner)")")"
  _billing_emit bills "$body" productName category startTime endTime payAmount
}

_billing_fixed_term() {
  local start end
  start="$(nv::args_get_uint start)" || exit 2
  end="$(nv::args_get_uint end)" || exit 2
  local body
  body="$(nv::http_basic GET "/billing/bill/monthly/list$(nv::query_params \
    category "$(nv::args_get category)" \
    productName "$(nv::args_get product)" \
    startTime "$start" \
    endTime "$end" \
    ownerId "$(nv::args_get owner)")")"
  _billing_emit bills "$body" productName tradeType cycle payAmount
}

_billing_apikey() {
  local usage="usage: nv billing apikey --cycle Hour|Day|Week|Month --start <unix-s> --end <unix-s>
              [--category <c>] [--product <n>] [--json] [--jq <f>]"
  local cycle start end
  _billing_require_cycle cycle "$usage"
  start="$(nv::args_get_uint start)" || exit 2
  end="$(nv::args_get_uint end)" || exit 2
  [[ -n "$start" && -n "$end" ]] || nv::usage "$usage"
  local body
  body="$(nv::http_basic GET "/billing/apikey/bill/list$(nv::query_params \
    cycleType "$cycle" \
    startTime "$start" \
    endTime "$end" \
    category "$(nv::args_get category)" \
    productName "$(nv::args_get product)")")"
  _billing_emit bills "$body" apikeyName apikeyMask startTime endTime payAmount
}

_billing_transactions() {
  # pageNo/pageSize are REQUIRED by this endpoint, so the bare verb defaults
  # them rather than shipping an empty query for the API to reject.
  local page limit start end
  page="$(nv::args_get_uint page 1)" || exit 2
  limit="$(nv::args_get_uint limit "$NV_DEFAULT_PAGE_SIZE")" || exit 2
  start="$(nv::args_get_uint start)" || exit 2
  end="$(nv::args_get_uint end)" || exit 2
  local body
  body="$(nv::http_basic GET "/bill/transaction$(nv::query_params \
    pageNo "$page" \
    pageSize "$limit" \
    serialNumber "$(nv::args_get serial)" \
    transactionTimeStart "$start" \
    transactionTimeEnd "$end" \
    transactionType "$(nv::args_get type)" \
    transactionChannel "$(nv::args_get channel)" \
    status "$(nv::args_get status)" \
    orderType "$(nv::args_get order-type)")")"
  _billing_emit data "$body" serialNumber transactionTime transactionType transactionAmount state
}

###
### :::: documentation (nv doc billing) :::: ###################################
###

# doc: monthly
# List monthly bills (amounts, status, invoice link) from a start month.
#
# Usage: nv billing monthly [--month YYYY-MM] [--page N] [--limit N]
#                           [--json] [--jq <filter>]
#
# Options:
#   --month <YYYY-MM>  first month to report (default: API-chosen; data
#                      available from 2025-10)
#   --page N           page number, from 1
#   --limit N          page size
#   --jq <filter>      jq filter applied to the array
#   --json             print the unwrapped array raw
#
# Notes:
#   The API fills months starting from --month, so a page may hold more or
#   fewer rows than --limit and the response carries no total — walk pages
#   until a short one. Monthly totals are 1/10000-USD strings ("10000" = $1).
#   status is one of pending, outed, paid, overdue, voided.
#
# Examples:
# # Bills from December 2025
# $ nv billing monthly --month 2025-12
#
# API: GET /openapi/v1/billing/monthly/bill

# doc: usage
# List usage-based (pay-as-you-go) bill lines for a product category.
#
# Usage: nv billing usage --cycle Hour|Day|Week|Month --product-category <c>
#                         [--product <n>] [--category <c>] [--start <ts>]
#                         [--end <ts>] [--owner <id>] [--json] [--jq <filter>]
#
# Options:
#   --cycle <c>              billing granularity (required)
#   --product-category <c>   product type: gpu, llm, serverless, cloud_storage,
#                            gen_api, cloud_sandbox, llm_dedicated_endpoint,
#                            web_search, bare_metal, summary (required)
#   --product <n>            filter by product name (fuzzy)
#   --category <c>           product subcategory
#   --start <ts>             window start, Unix seconds (int64)
#   --end <ts>               window end, Unix seconds (int64)
#   --owner <id>             resource instance id
#   --jq <filter>            jq filter applied to the array
#   --json                   print the unwrapped array raw
#
# Notes:
#   No pagination: keep the window within 31 days (split longer ranges by
#   calendar month or week). payAmount is a 1/10000-USD string ("10000" = $1);
#   startTime/endTime columns are the bill's own Unix-seconds window.
#
# Examples:
# # Daily LLM bills for December 2025
# $ nv billing usage --cycle Day --product-category llm \
#     --start 1764547200 --end 1767225599
#
# API: GET /openapi/v1/billing/bill/list

# doc: fixed-term
# List fixed-term (subscription) bill lines.
#
# Usage: nv billing fixed-term [--category <c>] [--product <n>] [--start <ts>]
#                              [--end <ts>] [--owner <id>] [--json]
#                              [--jq <filter>]
#
# Options:
#   --category <c>   product type: summary, gpu, serverless, cloud_storage,
#                    local_storage, image, bare_metal
#   --product <n>    filter by product name (fuzzy)
#   --start <ts>     window start, Unix seconds (int64)
#   --end <ts>       window end, Unix seconds (int64)
#   --owner <id>     resource instance id
#   --jq <filter>    jq filter applied to the array
#   --json           print the unwrapped array raw
#
# Notes:
#   No pagination: keep the window within 31 days. Each line carries its
#   billing `cycle` (YYYY-MM) and tradeType (monthly_new_buy, monthly_re_buy,
#   monthly_re_config); payAmount is a 1/10000-USD string ("10000" = $1).
#
# Examples:
# # GPU subscription lines for December 2025
# $ nv billing fixed-term --category gpu --start 1764547200 --end 1767225599
#
# API: GET /openapi/v1/billing/bill/monthly/list

# doc: apikey
# List per-API-key bill lines for a window.
#
# Usage: nv billing apikey --cycle Hour|Day|Week|Month --start <ts> --end <ts>
#                          [--category <c>] [--product <n>] [--json]
#                          [--jq <filter>]
#
# Options:
#   --cycle <c>      billing granularity (required); window caps: Hour 7 days,
#                    Day/Week/Month 31 days
#   --start <ts>     window start, Unix seconds (required; data from
#                    2026-01-01)
#   --end <ts>       window end, Unix seconds (required; must be > --start)
#   --category <c>   product type: llm, gen_api, web_search
#   --product <n>    filter by product name (fuzzy)
#   --jq <filter>    jq filter applied to the array
#   --json           print the unwrapped array raw
#
# Notes:
#   No pagination. The window cap is server-enforced: exceeding it answers
#   HTTP 400 naming the limit and cycle, so split the range and retry.
#   apikeyMask shows the console name + masked key; ownerID is the API key id.
#
# Examples:
# # Hourly LLM spend per key for one day
# $ nv billing apikey --cycle Hour --category llm \
#     --start 1767225600 --end 1767311999
#
# API: GET /openapi/v1/billing/apikey/bill/list

# doc: transactions
# List wallet transactions (top-ups, refunds, charges).
#
# Usage: nv billing transactions [--page N] [--limit N] [--serial <s>]
#                                [--type <t>] [--channel <c>] [--status <s>]
#                                [--order-type <t>] [--start <ts>] [--end <ts>]
#                                [--json] [--jq <filter>]
#
# Options:
#   --page N         page number, from 1 (default: 1)
#   --limit N        page size (default: 20)
#   --serial <s>     transaction serial number
#   --type <t>       transaction type: recharge, refund, consume
#   --channel <c>    payment channel: AliPay, WeixinPay, PublicRemittance
#   --status <s>     transaction status: pending, success, failed, expired
#   --order-type <t> order type: recharge, refund
#   --start <ts>     window start, Unix seconds (int64)
#   --end <ts>       window end, Unix seconds (int64)
#   --jq <filter>    jq filter applied to the array
#   --json           print the unwrapped array raw
#
# Notes:
#   The only billing endpoint that requires pageNo/pageSize — the CLI defaults
#   them so the bare verb works, and reports no page hint beyond the row set.
#   The response's `total` is visible via --json on the raw envelope
#   (`nv api GET /bill/transaction --ns basic`); the table shows
#   transactionAmount as a 1/10000-USD string ("10000" = $1).
#
# Examples:
# # Latest 20 transactions
# $ nv billing transactions
# # December 2025 top-ups
# $ nv billing transactions --type recharge \
#     --start 1764547200 --end 1767225599
#
# API: GET /openapi/v1/bill/transaction

nv::cmd_billing() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  monthly) _billing_monthly ;;
  usage) _billing_usage ;;
  fixed-term) _billing_fixed_term ;;
  apikey) _billing_apikey ;;
  transactions) _billing_transactions ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv billing <verb> [flags]
  monthly       [--month YYYY-MM] [--page N] [--limit N]     monthly bills
  usage         --cycle <c> --product-category <c> [...]     pay-as-you-go lines
  fixed-term    [--category <c>] [--start <ts>] [--end <ts>] subscription lines
  apikey        --cycle <c> --start <ts> --end <ts> [...]    per-API-key lines
  transactions  [--page N] [--limit N] [--type <t>] [...]    wallet transactions
  (money fields are 1/10000-USD strings; windows are Unix seconds unless noted)
EOF
    ;;
  *) nv::usage "unknown billing verb: '$verb'" ;;
  esac
}
