# nv template create
Create a template from an image.

```
nv template create --name <n> --type <t> --image <img>
                          [--env K=V] [--port p[:proto]] [--force]
```

## Options

```
  --name <n>        template name (required; enables idempotent re-runs)
  --type <t>        template type (required; `instance` is the only value
                    Novita's docs enumerate)
  --image <img>     container image (required)
  --env K=V         environment variable (repeatable)
  --port p[:proto]  exposed port; proto tcp|http, default tcp (repeatable)
  --force           create even when the name is taken
```

## Notes
  Creation is idempotent by name; --force POSTs regardless. The response
  carries the new id under template_id, and the id is printed on stdout,
  so `id=$(nv template create …)` captures just the id.

**API:** `POST /gpus/v2/templates`

