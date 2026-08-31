# nv billing monthly
List monthly bills (amounts, status, invoice link) from a start month.

```
nv billing monthly [--month YYYY-MM] [--page N] [--limit N]
                          [--json] [--jq <filter>]
```

## Options

```
  --month <YYYY-MM>  first month to report (default: API-chosen; data
                     available from 2025-10)
  --page N           page number, from 1
  --limit N          page size
  --jq <filter>      jq filter applied to the array
  --json             print the unwrapped array raw
```

## Notes
  The API fills months starting from --month, so a page may hold more or
  fewer rows than --limit and the response carries no total — walk pages
  until a short one. Monthly totals are 1/10000-USD strings ("10000" = $1).
  status is one of pending, outed, paid, overdue, voided.

## Examples

```
# Bills from December 2025
$ nv billing monthly --month 2025-12
```

**API:** `GET /openapi/v1/billing/monthly/bill`

