# nv cluster
Clusters: Novita's datacentre catalog (read-only).
A cluster is a physical datacentre region that hosts GPU instances and pins
network storage. The v1 namespace exposes it read-only — there is no create;
use it to discover cluster ids for `nv volume create --cluster`.

```
nv cluster <verb> [flags]
```

## Commands

- [`nv cluster list`](cluster-list.md) — List clusters (datacentres) as a table: id, name.
