# nv account
Show the account's Novita balance and credit.
One read-only GET in the basic namespace (/openapi/v1). The answer is a bare
JSON object — no `data` wrapper — of five string fields denominated in
1/10000 USD ("10000" = $1.00), so the human view prints it as a key:value
table and leaves the raw strings untouched; --json prints the API body
verbatim for scripting.

```
nv account [balance] [--json] [--jq <filter>]
```

## Arguments

```
  balance  the only verb; implied when omitted
```

## Options

```
  --json         print the raw API response
  --jq <filter>  jq filter applied to the response (implies JSON output)
```

## Examples

```
# Balance as a key:value table
$ nv account

# Just the spendable balance, raw 1/10000-USD string
$ nv account balance --jq .availableBalance
```

**API:** `GET /openapi/v1/billing/balance/detail`

## Commands

- [`nv account balance`](account-balance.md) — Show the account's balance, credit limit, and pending charges.
