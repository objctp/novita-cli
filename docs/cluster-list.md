# nv cluster list
List clusters (datacentres) as a table: id, name.

```
nv cluster list [--json] [--jq <filter>]
```

## Notes
  Read-only: the v1 namespace exposes clusters for discovery only, with no
  create. Each record also carries the available GPU types and whether the
  cluster supports network storage — use --json to see them.

**API:** `GET /gpu-instance/openapi/v1/clusters`

