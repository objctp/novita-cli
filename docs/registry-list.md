# nv registry list
List container-registry auths.

```
nv registry list [--json] [--jq <filter>] [--page N] [--limit N]
```

## Notes
  Each auth's id feeds `nv pod create --registry <id>` /
  `nv serverless create --registry <id>`. The CLI is read-only by design —
  credentials with passwords are console-managed — although the API does
  document save/delete routes. The record shape is not fully documented,
  so prefer --json when scripting.

**API:** `GET /gpu-instance/openapi/v1/repository/auths`

