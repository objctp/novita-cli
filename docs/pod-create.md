# nv pod create
Create a GPU instance.

```
nv pod create [--name <n>] --product <id> --image <img>
                     [--gpu-count N] [--rootfs-gb N] [--region <id,…>]
                     [--env K=V]… [--port <p>[:<proto>]]…
                     [--volume <storage-id>:<mount>]…
                     [--registry <auth-id>] [--entrypoint <cmd>]
                     [--command <args>] [--jupyter [--jupyter-port N]] [--force]
```

## Options

```
  --name <n>            instance name (enables idempotent re-runs)
  --product <id>        GPU product id — see `nv catalog gpu` (required)
  --image <img>         container image (required)
  --gpu-count N         number of GPUs (default: product default)
  --rootfs-gb N         system disk size in GB (default: 20)
  --region <id,…>       candidate regions, csv or repeated
  --env K=V             environment variable (repeatable)
  --port p[:proto]      exposed port; proto tcp|http|https (repeatable)
  --volume id:path      network-storage mount (repeatable; default /data)
  --registry <auth-id>  container-registry auth id — see `nv registry list`
  --entrypoint <cmd>    container entrypoint
  --command <args>      container command/arguments
  --jupyter             enable the Jupyter tool (port 8888, http)
  --force               create even when the name is taken
```

## Notes
  Creation is idempotent by name: where an instance of that name already
  exists, the CLI prints its id and skips the POST. --force sends the
  request regardless.
  The new id is printed on stdout and the confirmation on stderr, so
  `id=$(nv pod create …)` captures just the id.

## Examples

```
# Create a single-GPU dev box with Jupyter
$ nv pod create --name dev --product <id> \
    --image docker.io/library/ubuntu:22.04 --jupyter
```

**API:** `POST /gpus/v2/instances`

