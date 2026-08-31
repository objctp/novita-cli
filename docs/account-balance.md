# nv account balance
Show the account's balance, credit limit, and pending charges.

```
nv account balance [--json] [--jq <filter>]
```

## Options

```
  --json         print the raw API response
  --jq <filter>  jq filter applied to the response (implies JSON output)
```

## Notes
  The response is a bare object (no `data` wrapper) of string fields in
  1/10000 USD ("10000" = $1.00): availableBalance, cashBalance, creditLimit,
  pendingCharges, outstandingInvoices. The human view is a key:value table
  over those raw strings; use --json when scripting.

## Examples

```
# Balance as a key:value table
$ nv account balance

# Spendable balance only
$ nv account balance --jq .availableBalance
```

**API:** `GET /openapi/v1/billing/balance/detail`

