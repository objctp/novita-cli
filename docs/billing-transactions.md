# nv billing transactions
List wallet transactions (top-ups, refunds, charges).

```
nv billing transactions [--page N] [--limit N] [--serial <s>]
                               [--type <t>] [--channel <c>] [--status <s>]
                               [--order-type <t>] [--start <ts>] [--end <ts>]
                               [--json] [--jq <filter>]
```

## Options

```
  --page N         page number, from 1 (default: 1)
  --limit N        page size (default: 20)
  --serial <s>     transaction serial number
  --type <t>       transaction type: recharge, refund, consume
  --channel <c>    payment channel: AliPay, WeixinPay, PublicRemittance
  --status <s>     transaction status: pending, success, failed, expired
  --order-type <t> order type: recharge, refund
  --start <ts>     window start, Unix seconds (int64)
  --end <ts>       window end, Unix seconds (int64)
  --jq <filter>    jq filter applied to the array
  --json           print the unwrapped array raw
```

## Notes
  The only billing endpoint that requires pageNo/pageSize — the CLI defaults
  them so the bare verb works, and reports no page hint beyond the row set.
  The response's `total` is visible via --json on the raw envelope
  (`nv api GET /bill/transaction --ns basic`); the table shows
  transactionAmount as a 1/10000-USD string ("10000" = $1).

## Examples

```
# Latest 20 transactions
$ nv billing transactions

# December 2025 top-ups
$ nv billing transactions --type recharge \
    --start 1764547200 --end 1767225599
```

**API:** `GET /openapi/v1/bill/transaction`

