# nv billing apikey
List per-API-key bill lines for a window.

```
nv billing apikey --cycle Hour|Day|Week|Month --start <ts> --end <ts>
                         [--category <c>] [--product <n>] [--json]
                         [--jq <filter>]
```

## Options

```
  --cycle <c>      billing granularity (required); window caps: Hour 7 days,
                   Day/Week/Month 31 days
  --start <ts>     window start, Unix seconds (required; data from
                   2026-01-01)
  --end <ts>       window end, Unix seconds (required; must be > --start)
  --category <c>   product type: llm, gen_api, web_search
  --product <n>    filter by product name (fuzzy)
  --jq <filter>    jq filter applied to the array
  --json           print the unwrapped array raw
```

## Notes
  No pagination. The window cap is server-enforced: exceeding it answers
  HTTP 400 naming the limit and cycle, so split the range and retry.
  apikeyMask shows the console name + masked key; ownerID is the API key id.

## Examples

```
# Hourly LLM spend per key for one day
$ nv billing apikey --cycle Hour --category llm \
    --start 1767225600 --end 1767311999
```

**API:** `GET /openapi/v1/billing/apikey/bill/list`

