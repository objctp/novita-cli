# nv registry
Container-registry auths: credentials Novita uses to pull private images.
Referenced as registry_auth_id in instance/endpoint create bodies
(`nv pod create --registry <id>`). The API does document save/delete routes
(POST /repository/auth/save|delete), but the CLI stays read-only by design:
credentials carrying passwords are managed in the Novita console, and nv
deliberately never handles them.

```
nv registry <verb> [flags]
##
```

## Commands

- [`nv registry list`](registry-list.md) — List container-registry auths.
