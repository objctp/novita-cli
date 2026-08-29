# nv catalog regions
List regions with their supported GPU types.

```
nv catalog regions [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## Notes
  Each region carries its id, name, gpus[] and feature flags (network
  volume, instance networking). Region ids feed --region on pod/serverless
  create.

**API:** `GET /gpus/v2/regions?limit=N&cursor=<c>`

