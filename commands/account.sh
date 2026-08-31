#!/usr/bin/env bash
#
# Show the account's Novita balance and credit.
#
# One read-only GET in the basic namespace (/openapi/v1). The answer is a bare
# JSON object — no `data` wrapper — of five string fields denominated in
# 1/10000 USD ("10000" = $1.00), so the human view prints it as a key:value
# table and leaves the raw strings untouched; --json prints the API body
# verbatim for scripting.
#
# Usage: nv account [balance] [--json] [--jq <filter>]
#
# Arguments:
#   balance  the only verb; implied when omitted
#
# Options:
#   --json         print the raw API response
#   --jq <filter>  jq filter applied to the response (implies JSON output)
#
# Examples:
# # Balance as a key:value table
# $ nv account
# # Just the spendable balance, raw 1/10000-USD string
# $ nv account balance --jq .availableBalance
#
# API: GET /openapi/v1/billing/balance/detail
#

_account_balance() {
  local body
  body="$(nv::http_basic GET /billing/balance/detail)"
  if nv::args_has json; then
    printf '%s\n' "$body"
    return 0
  fi
  local jqf
  jqf="$(nv::args_get jq)"
  if [[ -n "$jqf" ]]; then
    printf '%s' "$body" | jq -r "$jqf"
    return 0
  fi
  # Bare object -> one-row-per-field table. Fields are documented required={false},
  # so absent keys simply render empty rather than failing the render.
  local rows
  rows="$(printf '%s' "$body" | jq -c 'to_entries | map({field: .key, value: (.value // "")})')"
  nv::table "$rows" field value
}

###
### :::: documentation (nv doc account) :::: ###################################
###

# doc: balance
# Show the account's balance, credit limit, and pending charges.
#
# Usage: nv account balance [--json] [--jq <filter>]
#
# Options:
#   --json         print the raw API response
#   --jq <filter>  jq filter applied to the response (implies JSON output)
#
# Notes:
#   The response is a bare object (no `data` wrapper) of string fields in
#   1/10000 USD ("10000" = $1.00): availableBalance, cashBalance, creditLimit,
#   pendingCharges, outstandingInvoices. The human view is a key:value table
#   over those raw strings; use --json when scripting.
#
# Examples:
# # Balance as a key:value table
# $ nv account balance
# # Spendable balance only
# $ nv account balance --jq .availableBalance
#
# API: GET /openapi/v1/billing/balance/detail

nv::cmd_account() {
  # `balance` is implied, so only a leading non-flag token is a verb — flags
  # like `nv account --json` must pass through to the parser untouched.
  local verb="balance"
  case "${1:-}" in
  "") ;;
  -*) ;;
  *)
    verb="$1"
    shift || true
    ;;
  esac
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  balance) _account_balance ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv account [balance] [--json] [--jq <f>]
  balance   show balance, credit limit, and pending charges (implied verb)
            (fields are 1/10000-USD strings; use --json when scripting)
EOF
    ;;
  *) nv::usage "unknown account verb: '$verb'" ;;
  esac
}
