#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/paginate.sh"
  source "$RP_ROOT/lib/transport.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/resource.sh"
  source "$RP_ROOT/commands/cluster.sh"
  source "$RP_ROOT/commands/registry.sh"
  source "$RP_ROOT/commands/template.sh"
  eval "$_opts"
}

function set_up() {
  CAP_CAPTURE="$(mktemp)"
  CAP_STUB_BODY='{"data":[]}'
  nv::http() {
    printf '%s %s\n' "$1" "$2" >>"$CAP_CAPTURE"
    printf '%s' "$CAP_STUB_BODY"
  }
  nv::http_v1() {
    printf '%s %s\n' "$1" "$2" >>"$CAP_CAPTURE"
    printf '%s' "$CAP_STUB_BODY"
  }
}

function tear_down() {
  rm -f "$CAP_CAPTURE"
}

# Clusters: read-only v1 catalog.
function test_cluster_list_routes_to_the_v1_clusters_path() {
  nv::cmd_cluster list >/dev/null 2>&1
  assert_contains "GET /clusters" "$(<"$CAP_CAPTURE")"
}

function test_cluster_list_tables_id_and_name() {
  CAP_STUB_BODY='{"data":[{"id":"5","name":"EU-01","availableGpuType":["RTX 4090"],"supportNetworkStorage":true}]}'
  local out
  out="$(nv::cmd_cluster list 2>/dev/null)"
  assert_contains "EU-01" "$out"
}

# Registry: read-only v1 auth list with a defensive reshape.
function test_registry_list_routes_to_the_v1_auths_path() {
  nv::cmd_registry list >/dev/null 2>&1
  assert_contains "GET /repository/auths" "$(<"$CAP_CAPTURE")"
}

function test_registry_list_projects_auth_fields() {
  CAP_STUB_BODY='{"data":[{"id":"auth-1","username":"deployer","registryUrl":"docker.io"}]}'
  local out
  out="$(nv::cmd_registry list 2>/dev/null)"
  assert_contains "auth-1" "$out"
  assert_contains "deployer" "$out"
}

# Template: v2 list confirmed.
function test_template_list_routes_to_the_v2_templates_path() {
  nv::cmd_template list >/dev/null 2>&1
  assert_contains "GET /templates" "$(<"$CAP_CAPTURE")"
}

function test_template_create_posts_name_type_and_image() {
  local out
  CAP_STUB_BODY='{"template_id":"tpl-1"}'
  out="$(nv::cmd_template create --name t1 --type instance --image nginx 2>/dev/null)"
  assert_equals "tpl-1" "$out"
  assert_contains "POST /templates" "$(<"$CAP_CAPTURE")"
}

function test_main_shell_routing_through_the_public_dispatchers() {
  nv::cmd_cluster list >/dev/null 2>&1
  assert_contains "GET /clusters" "$(<"$CAP_CAPTURE")"
  nv::cmd_registry list >/dev/null 2>&1
  assert_contains "GET /repository/auths" "$(<"$CAP_CAPTURE")"
  nv::cmd_template list >/dev/null 2>&1
  assert_contains "GET /templates" "$(<"$CAP_CAPTURE")"
}
