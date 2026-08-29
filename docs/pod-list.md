# nv pod list
List your GPU instances as a table: id, name, status, region.

```
nv pod list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## Options

```
  --limit N      page size forwarded to the API (v2 cursor pagination)
  --cursor <c>   opaque cursor of the next page; pairs with --limit
  --jq <filter>  jq filter applied to the array
  --json         print the raw API response
```

## Notes
  Pages are fetched server-side (v2 cursor pagination). When more pages
  exist, the next cursor is printed to stderr, leaving stdout clean for
  scripts; pass it back with --cursor.

**API:** `GET /gpus/v2/instances?limit=N&cursor=<c>`

