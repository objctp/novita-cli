#!/usr/bin/env bash
#
# Public catalog: GPU products per category, and regions.
#
# The products endpoint requires BOTH query params — type=gpu and
# category=instance|serverless — or the API answers 400, so each verb pins
# them. Product ids feed `nv pod create --product` / `nv serverless create
# --product`; region ids feed --region / --region-id.
#
# Usage: nv catalog <verb> [flags]
#

_catalog_products() {
  local category="$1"
  local body arr
  body="$(nv::http GET "/products$(nv::query_params type gpu category "$category" \
    limit "$(nv::args_get limit)" cursor "$(nv::args_get cursor)")")"
  arr="$(nv::unwrap data "$body")"
  nv::more_hint "$body"
  local jqf
  jqf="$(nv::args_get jq)"
  [[ -z "$jqf" ]] || arr="$(printf '%s' "$arr" | jq -c "$jqf")" || nv::die "invalid --jq filter: $jqf"
  nv::emit_json_or "$arr" nv::table "$arr" id name
}

###
### :::: documentation (nv doc catalog) :::: ###################################
###

# doc: gpu
# List GPU products rentable as instances (pods).
#
# Usage: nv catalog gpu [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Notes:
#   The API requires type=gpu AND category=instance, which this verb pins.
#   Product ids feed `nv pod create --product`.
#
# API: GET /gpus/v2/products?type=gpu&category=instance

# doc: serverless
# List GPU products rentable by serverless endpoints.
#
# Usage: nv catalog serverless [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Notes:
#   Same endpoint as `nv catalog gpu` with category=serverless pinned.
#   Product ids feed `nv serverless create --product`.
#
# API: GET /gpus/v2/products?type=gpu&category=serverless

# doc: regions
# List regions with their supported GPU types.
#
# Usage: nv catalog regions [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Notes:
#   Each region carries its id, name, gpus[] and feature flags (network
#   volume, instance networking). Region ids feed --region on pod/serverless
#   create.
#
# API: GET /gpus/v2/regions?limit=N&cursor=<c>

nv::cmd_catalog() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  gpu) _catalog_products instance ;;
  serverless) _catalog_products serverless ;;
  regions)
    local body arr
    body="$(nv::http GET "/regions$(nv::query_params limit "$(nv::args_get limit)" \
      cursor "$(nv::args_get cursor)")")"
    arr="$(nv::unwrap data "$body")"
    nv::more_hint "$body"
    local jqf
    jqf="$(nv::args_get jq)"
    [[ -z "$jqf" ]] || arr="$(printf '%s' "$arr" | jq -c "$jqf")" || nv::die "invalid --jq filter: $jqf"
    nv::emit_json_or "$arr" nv::table "$arr" id name
    ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv catalog <verb> [flags]
  gpu          products rentable as instances   (type=gpu&category=instance)
  serverless   products rentable by endpoints   (type=gpu&category=serverless)
  regions      regions and their supported GPUs
  (all verbs: --json, --jq <f>, --limit N, --cursor <c>)
EOF
    ;;
  *) nv::usage "unknown catalog verb: '$verb'" ;;
  esac
}
