# nv billing
Query Novita bills: monthly, usage, fixed-term, and more.
Five read-only GETs in the basic namespace (/openapi/v1). All money fields
are strings in 1/10000 USD ("10000" = $1.00); windows are Unix-seconds
timestamps except the monthly bill, which anchors on a YYYY-MM month. The
endpoints disagree on envelope and pagination — monthly/transactions wrap in
`data`, the three bill lists in `bills`, and only monthly (`page`) and
transactions (`pageNo`, required) paginate — so each verb pins its own query
params.

```
nv billing <verb> [flags]
```

## Commands

- [`nv billing monthly`](billing-monthly.md) — List monthly bills (amounts, status, invoice link) from a start month.
- [`nv billing usage`](billing-usage.md) — List usage-based (pay-as-you-go) bill lines for a product category.
- [`nv billing fixed-term`](billing-fixed-term.md) — List fixed-term (subscription) bill lines.
- [`nv billing apikey`](billing-apikey.md) — List per-API-key bill lines for a window.
- [`nv billing transactions`](billing-transactions.md) — List wallet transactions (top-ups, refunds, charges).
