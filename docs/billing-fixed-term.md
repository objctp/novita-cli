# nv billing fixed-term
List fixed-term (subscription) bill lines.

```
nv billing fixed-term [--category <c>] [--product <n>] [--start <ts>]
                             [--end <ts>] [--owner <id>] [--json]
                             [--jq <filter>]
```

## Options

```
  --category <c>   product type: summary, gpu, serverless, cloud_storage,
                   local_storage, image, bare_metal
  --product <n>    filter by product name (fuzzy)
  --start <ts>     window start, Unix seconds (int64)
  --end <ts>       window end, Unix seconds (int64)
  --owner <id>     resource instance id
  --jq <filter>    jq filter applied to the array
  --json           print the unwrapped array raw
```

## Notes
  No pagination: keep the window within 31 days. Each line carries its
  billing `cycle` (YYYY-MM) and tradeType (monthly_new_buy, monthly_re_buy,
  monthly_re_config); payAmount is a 1/10000-USD string ("10000" = $1).

## Examples

```
# GPU subscription lines for December 2025
$ nv billing fixed-term --category gpu --start 1764547200 --end 1767225599
```

**API:** `GET /openapi/v1/billing/bill/monthly/list`

