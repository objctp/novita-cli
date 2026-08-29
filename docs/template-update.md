# nv template update
Update a template (the update spec takes the create key set, none required).

```
nv template update <id> [--name <n>] [--type <t>] [--image <img>]
                              [--registry <auth-id>] [--entrypoint <cmd>]
                              [--command <args>] [--rootfs-gb N]
                              [--env K=V] [--port p[:proto]]
```

## Options

```
  --name <n>            template name
  --type <t>            template type (`instance` is the documented value)
  --image <img>         container image
  --registry <auth-id>  container-registry auth id — see `nv registry list`
  --entrypoint <cmd>    container entrypoint
  --command <args>      container command/arguments
  --rootfs-gb N         system disk size in GB
  --env K=V             environment variable (repeatable)
  --port p[:proto]      exposed port; proto tcp|http, default tcp (repeatable)
```

## Notes
  Only the set flags are sent; with none, the command exits with a usage
  error rather than an empty PUT. The update answers the same
  {"template_id": …} shape as create.

**API:** `PUT /gpus/v2/templates/{id}`

