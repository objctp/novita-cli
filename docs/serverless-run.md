# nv serverless run
Invoke a job: sync endpoints POST the endpoint's url directly, async
endpoints submit to the shared gateway.

```
nv serverless run <id> [--input <json>|@file] [--path <p>]
```

## Arguments

```
  <id>             endpoint id — from `nv serverless list`
```

## Options

```
  --input <json>   request payload; inline JSON or @file
  --path <p>       sync only: path appended to the endpoint's url
                   (default: none — the url is POSTed bare)
```

## Notes
  Dispatched on the endpoint record's type. A sync endpoint's `url` serves
  your HTTP service on arbitrary paths (e.g. --path /v1/chat/completions);
  the payload is sent verbatim. An async endpoint submits {"input": …} to
  the shared gateway (payloads already carrying an input key pass through),
  which answers {id, status: PENDING}; poll with `nv serverless status`,
  abort with `nv serverless cancel`. The sync surface can block on the
  customer's service: invoke budget 300 s, override with NV_TIMEOUT_INVOKE.
  --sync was removed: no /runsync route is documented.

## Examples

```
# Sync endpoint: chat completion against the customer path
$ nv serverless run ep123 --path /v1/chat/completions --input '{"messages":[…]}'

# Async endpoint: fire and forget, then poll
$ nv serverless run ep123 --input '{"prompt":"hello"}'
$ nv serverless status ep123 <job_id>
```

**API:** `GET /gpus/v2/endpoints/{id}, then POST {url}{path} (sync) or`

     POST https://async-public.serverless.novita.ai/v1/{endpoint_name}/run
     (async)
