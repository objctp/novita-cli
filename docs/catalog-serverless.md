# nv catalog serverless
List GPU products rentable by serverless endpoints.

```
nv catalog serverless [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## Notes
  Same endpoint as `nv catalog gpu` with category=serverless pinned.
  Product ids feed `nv serverless create --product`.

**API:** `GET /gpus/v2/products?type=gpu&category=serverless`

