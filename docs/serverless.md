# nv serverless
Serverless GPU endpoints (BYO-container).
An endpoint is an autoscaling pool of worker containers running your image:
Novita schedules workers per the worker_config, scales on the policy, and
health-checks them. Jobs are invoked against the endpoint's own `url` field
(a customer-owned host), not a shared Novita data-plane host.

```
nv serverless <verb> [flags]
```

## Commands

- [`nv serverless list`](serverless-list.md) — List your serverless endpoints as a table: id, name, url, region_id.
- [`nv serverless get`](serverless-get.md) — Show one endpoint's full record, including its invoke `url`.
- [`nv serverless create`](serverless-create.md) — Create a serverless endpoint (BYO container).
- [`nv serverless update`](serverless-update.md) — Patch an endpoint's scaling fields.
- [`nv serverless delete`](serverless-delete.md) — Delete a serverless endpoint permanently.
- [`nv serverless run`](serverless-run.md) — Invoke a job on the endpoint's own URL.
