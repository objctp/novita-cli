# nv volume
Network storage: durable volumes mountable by instances and endpoints.
Storage lives in one cluster (datacentre) and outlives every workload that
mounts it. The v1 namespace splits the routes: list under
/networkstorages/list (GET, pageNo/pageSize), and the writes under
/networkstorage/{create,update,delete} (POST, camelCase bodies). The create
response is a BARE JSON STRING holding the new storage id — nv::extract_id
handles both shapes.

```
nv volume <verb> [flags]
```

## Commands

- [`nv volume list`](volume-list.md) — List network storage as a table: storageId, storageName, storageSize, clusterName.
- [`nv volume create`](volume-create.md) — Create network storage in a cluster.
- [`nv volume delete`](volume-delete.md) — Delete network storage permanently.
- [`nv volume update`](volume-update.md) — Rename or resize network storage.
