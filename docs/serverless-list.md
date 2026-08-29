# nv serverless list
List your serverless endpoints as a table: id, name, url, region.

```
nv serverless list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## Options

```
  --limit N      page size forwarded to the API (v2 cursor pagination)
  --cursor <c>   opaque cursor of the next page; pairs with --limit
  --jq <filter>  jq filter applied to the array
  --json         print the raw API response
```

**API:** `GET /gpus/v2/endpoints?limit=N&cursor=<c>`

