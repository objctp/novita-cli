# nv serverless run
Invoke a job on the endpoint's own URL.

```
nv serverless run <id> [--input <json>|@file] [--sync]
```

## Arguments

```
  <id>             endpoint id — from `nv serverless list`
```

## Options

```
  --input <json>   request body; inline JSON or @file (default: empty)
  --sync           POST <url>/runsync instead of <url>/run (blocks on the job)
```

## Notes
  The endpoint record carries its own `url` field; the job goes there, not
  to a shared Novita host. Without --sync the call returns as soon as the
  job is accepted. The invoke budget is 300 s; override with NV_TIMEOUT_INVOKE.

## Examples

```
# Fire and forget
$ nv serverless run ep123 --input '{"prompt":"hello"}'

# Block until the job completes
$ nv serverless run ep123 --sync --input @job.json
```

**API:** `GET /gpus/v2/endpoints/{id}, then POST <url>/run|/runsync`

