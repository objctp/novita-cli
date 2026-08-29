# nv serverless health
Show an async endpoint's queue health: worker and job counters.

```
nv serverless health <id> [--json]
```

## Arguments

```
  <id>    endpoint id — from `nv serverless list`
```

**API:** `GET https://async-public.serverless.novita.ai/v1/{endpoint_name}/health`

