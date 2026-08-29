# nv template create
Create a template from an image.

```
nv template create --name <n> --image <img> [--env K=V] [--port p[:proto]]
```

## Notes
  The list path is confirmed, but Novita's docs do not confirm a create
  route; this verb POSTs /gpus/v2/templates per REST convention and may need
  adjusting once the route is verified.

**API:** `POST /gpus/v2/templates  (route unverified)`

