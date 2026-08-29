# nv serverless update
Patch an endpoint's scaling fields.

```
nv serverless update <id> [--name <n>] [--min N] [--max N]
                              [--idle S] [--concurrent N] [--json]
```

## Notes
  At least one flag is required; with none, the command exits with a usage
  error rather than sending an empty PATCH. The PATCH route follows the REST
  convention — Novita's docs confirm create but not update, so verify
  against the live API before scripting this verb.

**API:** `PATCH /gpus/v2/endpoints/{id}  (route unverified)`

