#!/usr/bin/env bash
#
# Clusters: Novita's datacentre catalog (read-only).
#
# A cluster is a physical datacentre region that hosts GPU instances and pins
# network storage. The v1 namespace exposes it read-only — there is no create;
# use it to discover cluster ids for `nv volume create --cluster`.
#
# Usage: nv cluster <verb> [flags]
#

###
### :::: documentation (nv doc cluster) :::: ###################################
###

# doc: list
# List clusters (datacentres) as a table: id, name.
#
# Usage: nv cluster list [--json] [--jq <filter>]
#
# Notes:
#   Read-only: the v1 namespace exposes clusters for discovery only, with no
#   create. Each record also carries the available GPU types and whether the
#   cluster supports network storage — use --json to see them.
#
# API: GET /gpu-instance/openapi/v1/clusters

nv::cmd_cluster() {
  local verb="${1:-help}"
  shift || true
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  list) nv::resource_list cluster id name ;;
  -h | --help | help)
    cat <<'EOF'
Usage: nv cluster <verb> [flags]
  list [--json] [--jq <f>]   (read-only datacentre catalog — no create)
EOF
    ;;
  *) nv::usage "unknown cluster verb: '$verb'" ;;
  esac
}
