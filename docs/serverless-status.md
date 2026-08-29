# nv serverless status
Poll one async job's status and output.

```
nv serverless status <id> <job_id> [--json]
```

## Arguments

```
  <id>      endpoint id — from `nv serverless list`
  <job_id>  job id — from `nv serverless run`
```

## Notes
  GETs the shared gateway (never the endpoint's url). Output is ≤ 4 MiB and
  retained for 6 hours after completion.

**API:** `GET https://async-public.serverless.novita.ai/v1/{endpoint_name}/status/{job_id}`

