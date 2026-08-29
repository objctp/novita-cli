# nv api
Raw namespaced call over nv's own transport.
This is the same transport every resource verb uses, exposed for scripting
and ad-hoc calls: it resolves the method, namespace, path, body, and optional
jq filter, then delegates to nv::http / nv::http_v1 — all curl, auth, timeout
and error policy live in lib/transport.sh behind that seam. It prints the
response body, and dies on HTTP 400 or above with the API's own message.

```
nv api <METHOD> <path> [--body <json>] [--ns v2|v1]
              [--jq <filter>] [--limit N] [--cursor <c>]
```

## Arguments

```
  <METHOD>     HTTP method: GET/POST/PUT/DELETE/... (case-insensitive)
  <path>       path under the namespace base (a leading / is optional)
```

## Options

```
  --body <json>  request body; prefix with @ to read a file
  --ns v2|v1     v2 = /gpus/v2 (default) | v1 = /gpu-instance/openapi/v1
  --jq <filter>  jq filter applied to the response (implies JSON output)
  --limit N      cap the number of (top-level-array) items returned
```

## Examples

```
# List instances (v2 default)
$ nv api GET /instances

# List clusters (v1 namespace)
$ nv api GET /clusters --ns v1

# Create an instance from a JSON body
$ nv api POST /instances --body '{"product_id":"…","image":"…"}'
```
