# nv billing usage
List usage-based (pay-as-you-go) bill lines for a product category.

```
nv billing usage --cycle Hour|Day|Week|Month --product-category <c>
                        [--product <n>] [--category <c>] [--start <ts>]
                        [--end <ts>] [--owner <id>] [--json] [--jq <filter>]
```

## Options

```
  --cycle <c>              billing granularity (required)
  --product-category <c>   product type: gpu, llm, serverless, cloud_storage,
                           gen_api, cloud_sandbox, llm_dedicated_endpoint,
                           web_search, bare_metal, summary (required)
  --product <n>            filter by product name (fuzzy)
  --category <c>           product subcategory
  --start <ts>             window start, Unix seconds (int64)
  --end <ts>               window end, Unix seconds (int64)
  --owner <id>             resource instance id
  --jq <filter>            jq filter applied to the array
  --json                   print the unwrapped array raw
```

## Notes
  No pagination: keep the window within 31 days (split longer ranges by
  calendar month or week). payAmount is a 1/10000-USD string ("10000" = $1);
  startTime/endTime columns are the bill's own Unix-seconds window.

## Examples

```
# Daily LLM bills for December 2025
$ nv billing usage --cycle Day --product-category llm \
    --start 1764547200 --end 1767225599
```

**API:** `GET /openapi/v1/billing/bill/list`

