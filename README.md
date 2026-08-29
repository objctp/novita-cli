# novita-cli (`nv`)

A POSIX-shell CLI for [Novita AI](https://novita.ai)'s GPU cloud — GPU instances
("pods"), serverless endpoints, the product catalog, templates, clusters,
network storage, and container-registry auths. Written in Bash + jq + curl,
with no dependencies beyond those three.

```
Usage: nv <resource> <verb> [flags]
```

## Install

```sh
git clone <this repo> && cd novita-cli
sudo ln -sf "$(pwd)/bin/nv" /usr/local/bin/nv   # or add ./bin to PATH
```

Requirements: Bash 5+, `jq`, `curl` (macOS: `brew install jq`; the system Bash
is 3.x — use Homebrew Bash).

## Quick start

```sh
export NOVITA_API_KEY=nv-...        # or: nv auth login --api-key nv-...
nv _ping                            # cheapest authenticated call
nv catalog gpu                      # products rentable as instances
nv catalog regions                  # regions and their GPUs
nv cluster list                     # datacentre clusters (v1, read-only)
nv volume create --name shared-data --size 100 --cluster 5
nv pod create --name dev --product <id> --image docker.io/library/ubuntu:22.04
nv pod stop <id> && nv pod start <id>
nv serverless create --name api --product <id> --image <img> \
    --app my-app --region <id> --min 0 --max 1 --idle 300
nv serverless run <id> --input '{"prompt":"hello"}' --sync
```

Add `--json` to any list/get for raw JSON, `--jq '<filter>'` to filter, and
`nv doc <resource> [verb]` for the full reference (arguments, caveats,
examples — rendered from the source comments).

## One host, two namespaces

Novita serves the whole GPU cloud from `https://api.novita.ai` under **two
namespaces** that differ in body casing and pagination:

| | v2 | v1 |
|---|---|---|
| Base | `/gpus/v2` | `/gpu-instance/openapi/v1` |
| Bodies | snake_case (`product_id`, `worker_config`) | camelCase (`clusterId`, `storageName`) |
| Pagination | `limit` + opaque `cursor` → `next_cursor`/`has_more` | `pageNo` + `pageSize` |
| Resources | pod, serverless, catalog, template | cluster, volume, registry |

`nv` routes each resource to its namespace automatically — you never pick one.
The `data` unwrap key is uniform across both.

## Resources

| Resource | Namespace | Verbs |
|---|---|---|
| `pod` | v2 `/instances` | list, get, create, start, stop, delete |
| `serverless` | v2 `/endpoints` | list, get, create, update, delete, run |
| `catalog` | v2 `/products`, `/regions` | gpu, serverless, regions |
| `template` | v2 `/templates` | list, create (create route unverified) |
| `cluster` | v1 `/clusters` | list (read-only) |
| `volume` | v1 `/networkstorages` | create, list |
| `registry` | v1 `/repository/auths` | list (read-only) |
| `auth` | — | login, logout, switch/use, list, status |
| `api` | both | raw namespaced call (`--ns v2\|v1`) |
| `doc` | — | embedded reference manual |

Notable behaviours:

- **Create is idempotent by name** — re-running with the same `--name` prints
  the existing id instead of POSTing; `--force` overrides.
- **Serverless run invokes the endpoint's own `url`** (from the endpoint
  record), not a shared Novita host. `/run` by default, `/runsync` with
  `--sync`.
- **Volume create answers a bare JSON string id** — `nv::extract_id` handles
  both shapes, so `id=$(nv volume create …)` always captures the id.
- **Distinct exit codes**: `0` ok · `1` general/API error · `2` usage ·
  `3` auth · `4` not-found · `130` interrupted.

## Credentials

Priority order: exported `NOVITA_API_KEY` / `NOVITA_API_KEY_FILE` → the active
account in `${XDG_CONFIG_HOME:-$HOME/.config}/novita/credentials.d/` →
`~/.config/novita/.env` → repo-local `.env`. Keys travel via temp files to
curl (never argv) and are suppressed from `set -x` traces.

```sh
nv auth login --name prod --api-key nv-...   # additive, marks active
nv auth switch work                          # change active account
nv --account prod pod list                   # one-off override
```

## Development

```sh
make lint     # shellcheck
make fmt      # shfmt -i 2
make test     # bashunit tests
make check    # lint + test
```

Tests run offline: HTTP doubles stand in for `nv::http` / `nv::http_v1` /
`nv::http_url`, so no network is touched. Layout:

```
bin/nv            entry point: .env loading, lib sourcing, dispatch
lib/              transport (one curl impl), http clients, args parser,
                  auth seam, JSON builders, pagination, resource descriptors
commands/         one module per resource + auth/api/doc meta commands
tests/            bashunit unit + functional suites
```

## Status / verification

Endpoints verified against the live docs (2026-08): v2 instance/endpoint
create bodies, v2 `limit`/`cursor` pagination, v1 storage list/create, v1
clusters and registry-auth lists. **Unverified** (documented as such in
`nv doc`): template create route, endpoint PATCH route. Auths are created in
the Novita console; the registry command is read-only.
