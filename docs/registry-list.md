# nv registry list
List container-registry auths.

```
nv registry list [--json] [--jq <filter>] [--page N] [--limit N]
```

## Notes
  Each auth's id feeds `nv pod create --registry <id>` /
  `nv serverless create --registry <id>`. The v1 namespace confirms only the
  list route; create and delete happen in the Novita console. The record
  shape is not fully documented, so prefer --json when scripting.

**API:** `GET /gpu-instance/openapi/v1/repository/auths`

