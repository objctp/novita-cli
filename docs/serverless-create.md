# nv serverless create
Create a serverless endpoint (BYO container).

```
nv serverless create --name <n> --product <id> --image <img>
                            --app <name> --region <id>
                            [--type sync|async] [--min N] [--max N]
                            [--idle S] [--concurrent N] [--gpu-count N]
                            [--rootfs-gb N] [--request-timeout S]
                            [--policy queue|concurrency] [--policy-value N]
                            [--env K=V]… [--port <p>]…
                            [--volume <storage-id>:<mount>]…
                            [--registry <auth-id>] [--health-path <p>]
                            [--health-port N] [--entrypoint <cmd>]
                            [--command <args>] [--force]
```

## Notes
  --type is sync|async (default sync); --policy is queue|concurrency.
  --port takes a bare integer 1-65535 — no ':protocol' suffix here.
  The API requires a worker_config with an explicit max_replicas, so a bare
  create sends --max 1; the scaling flags override.
  Creation is idempotent by name; --force POSTs regardless. min 0 scales to
  zero (cheap, cold starts); the policy arms map to Novita's queue-wait and
  per-worker request-count scalers.
  The new id is printed on stdout and the confirmation on stderr, so
  `id=$(nv serverless create …)` captures just the id.

## Examples

```
# Cold-start-to-zero endpoint with a health check
$ nv serverless create --name api --product <id> --image <img> \
    --app my-app --region <id> --min 0 --max 1 --idle 300 \
    --health-path /healthz --health-port 8080
```

**API:** `POST /gpus/v2/endpoints`

