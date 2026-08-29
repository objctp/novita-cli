# nv volume list
List network storage as a table: storageId, storageName, storageSize, clusterName.

```
nv volume list [--name <f>] [--id <f>] [--page N] [--limit N]
                      [--jq <filter>] [--json]
```

## Options

```
  --name <f>     filter by storage name
  --id <f>       filter by storage id
  --page N       page number (v1 pageNo)
  --limit N      page size (v1 pageSize)
  --jq <filter>  jq filter applied to the array
  --json         print the raw API response
```

## Notes
  The v1 namespace paginates with pageNo/pageSize — different from the v2
  cursor scheme. Ids land in the storageId field, not `id`.

**API:** `GET /gpu-instance/openapi/v1/networkstorages/list`

