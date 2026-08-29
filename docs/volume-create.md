# nv volume create
Create network storage in a cluster.

```
nv volume create --name <n> --size <gb> --cluster <id> [--force]
```

## Options

```
  --name <n>      storage name (required; enables idempotent re-runs)
  --size <gb>     capacity in GB (required)
  --cluster <id>  cluster id — see `nv cluster list` (required)
  --force         create even when the name is taken
```

## Notes
  Creation is idempotent by name: where storage of that name already exists,
  the CLI prints its id and skips the POST. --force sends the request
  regardless.
  The create response is a bare JSON string holding the new id (not an
  object) — `id=$(nv volume create …)` captures it either way.
  Storage is pinned to its cluster for life; workloads that mount it must
  run there.

## Examples

```
# Create 100 GB of storage in cluster 5
$ nv volume create --name shared-data --size 100 --cluster 5
```

**API:** `POST /gpu-instance/openapi/v1/networkstorage/create`

