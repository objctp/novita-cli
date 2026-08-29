# nv registry
Container-registry auths: credentials Novita uses to pull private images.
Referenced as registry_auth_id in instance/endpoint create bodies
(`nv pod create --registry <id>`). The v1 namespace confirms only the list
route — auths are normally created in the Novita console, so this command is
read-only.

```
nv registry <verb> [flags]
##
```

## Commands

- [`nv registry list`](registry-list.md) — List container-registry auths.
