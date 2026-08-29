# nv serverless cancel
Cancel one async job.

```
nv serverless cancel <id> <job_id> [--json]
```

## Arguments

```
  <id>      endpoint id — from `nv serverless list`
  <job_id>  job id — from `nv serverless run`
```

**API:** `POST https://async-public.serverless.novita.ai/v1/{endpoint_name}/cancel/{job_id}`

