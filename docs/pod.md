# nv pod
GPU instance lifecycle ("pods").
An instance is a rented GPU container: pick a product (GPU shape), an image,
and a region; Novita schedules it and bills while it runs. Start/stop keeps
the instance (and its rootfs) around without paying for the GPU.

```
nv pod <verb> [flags]
```

## Commands

- [`nv pod list`](pod-list.md) — List your GPU instances as a table: id, name, status, region.
- [`nv pod get`](pod-get.md) — Show one instance's full record.
- [`nv pod create`](pod-create.md) — Create a GPU instance.
- [`nv pod start`](pod-start.md) — Start a stopped instance.
- [`nv pod stop`](pod-stop.md) — Stop a running instance (keeps the rootfs; stops GPU billing).
- [`nv pod delete`](pod-delete.md) — Delete an instance permanently (rootfs included).
