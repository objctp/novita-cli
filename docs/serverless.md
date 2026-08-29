# nv serverless
Serverless GPU endpoints (BYO-container).
An endpoint is an autoscaling pool of worker containers running your image:
Novita schedules workers per the worker_config, scales on the policy, and
health-checks them. Invocation is TWO-SURFACE: a sync endpoint's own `url`
serves your HTTP service on arbitrary paths, whilst an async endpoint's jobs
go through the shared gateway host (run/status/cancel/health) — never to the
endpoint's url.

```
nv serverless <verb> [flags]
```

## Commands

- [`nv serverless list`](serverless-list.md) — List your serverless endpoints as a table: id, name, url, region_id.
- [`nv serverless get`](serverless-get.md) — Show one endpoint's full record, including its invoke `url`.
- [`nv serverless create`](serverless-create.md) — Create a serverless endpoint (BYO container).
- [`nv serverless update`](serverless-update.md) — Patch an endpoint's scaling fields.
- [`nv serverless delete`](serverless-delete.md) — Delete a serverless endpoint permanently.
- [`nv serverless run`](serverless-run.md) — Invoke a job: sync endpoints POST the endpoint's url directly, async
- [`nv serverless status`](serverless-status.md) — Poll one async job's status and output.
- [`nv serverless cancel`](serverless-cancel.md) — Cancel one async job.
- [`nv serverless health`](serverless-health.md) — Show an async endpoint's queue health: worker and job counters.
