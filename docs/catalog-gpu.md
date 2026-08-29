# nv catalog gpu
List GPU products rentable as instances (pods).

```
nv catalog gpu [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## Notes
  The API requires type=gpu AND category=instance, which this verb pins.
  Product ids feed `nv pod create --product`.

**API:** `GET /gpus/v2/products?type=gpu&category=instance`

