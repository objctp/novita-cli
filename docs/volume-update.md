# nv volume update
Rename or resize network storage.

```
nv volume update <id> [--name <n>] [--size <gb>]
```

## Options

```
  --name <n>    new storage name
  --size <gb>   new capacity in GB
```

## Notes
  At least one flag is required; with none, the command exits with a usage
  error rather than sending an empty update. Resizing is subject to the
  API's rules — a shrink may be rejected server-side.

**API:** `POST /gpu-instance/openapi/v1/networkstorage/update`

