#!/usr/bin/env bash
# jq-backed JSON builders (string / array / object / merge) used to assemble REST
# request bodies, plus nv::json_pretty for human-mode output. Namespace-specific
# request shapes live here too: v2 bodies are snake_case (worker_config,
# health_check, product_id, envs[{key,value}], …); v1 bodies are camelCase
# (clusterId, storageName, storageSize) and are assembled at their call sites in
# commands/*.sh from these same generic primitives.
[[ -n "${_NV_JSON:-}" ]] && return 0
_NV_JSON=1

_json_merge() { jq -c -n --argjson a "$1" --argjson b "$2" '$a * $b'; }

nv::json_str() { jq -Rc . <<<"$1"; }

nv::json_pretty() { jq . <<<"$1"; }

nv::json_array() {
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$@" | jq -R . | jq -sc .
  else
    printf '[]'
  fi
}

# Build a JSON object from alternating key/value pairs.
# Arguments:
#   $1 $3 $5 … - key: object key
#   $2 $4 $6 … - value: PRE-ENCODED JSON (it lands in `jq --argjson`)
# Returns:
#   0 - prints the assembled object to stdout
# Wrap raw strings with nv::json_str first, or jq fails at runtime.
nv::json_obj() {
  local obj='{}'
  local k v
  while [[ $# -ge 2 ]]; do
    k="$1"
    v="$2"
    shift 2
    obj="$(jq -c -n --argjson cur "$obj" --arg k "$k" --argjson v "$v" '$cur + {($k): $v}')"
  done
  printf '%s' "$obj"
}

# Merge {key: val} into the object named by $1.
# Arguments:
#   $1 - dest: caller's variable name (nameref) to merge into
#   $2 - key: object key
#   $3 - val: value; an empty $3 is a silent no-op
# Returns:
#   0 - merged (or no-op when $3 is empty)
# The silent empty-skip is what request-body assembly relies on to skip unset fields.
nv::obj_set() {
  local -n dest="$1"
  local key="$2" val="$3"
  [[ -n "$val" ]] || return 0
  dest="$(_json_merge "$dest" "$(nv::json_obj "$key" "$val")")"
}

# nv::obj_set for RAW STRING values: skips empty strings (like obj_set) and
# JSON-encodes the value first. The two-step guard matters because
# nv::json_str("") yields `""` — a NON-empty (quoted) value obj_set would
# happily set, so an unset --name must be checked before encoding.
# Arguments:
#   $1 - dest: caller's variable name (nameref) to merge into
#   $2 - key: object key
#   $3 - val: raw string; an empty $3 is a silent no-op
# Returns:
#   0 - merged (or no-op when $3 is empty)
nv::obj_set_str() {
  [[ -n "$3" ]] || return 0
  nv::obj_set "$1" "$2" "$(nv::json_str "$3")"
}

nv::csv_to_jsonarray() {
  local -a a
  mapfile -t a < <(nv::split_csv "$1")
  nv::json_array "${a[@]}"
}

###
### :::: v2 request-body shapes (snake_case) :::: ##############################
###
# Leaf builders for the API object shapes that repeat across commands. Keeping
# them here routes every request body through one seam and makes each shape
# unit-testable in isolation.

# v2 envs: newline-delimited K=V pairs (one per --env) -> [{"key":K,"value":V}].
# Each pair splits on the FIRST '=' only, so a value may itself contain '=' or
# ',' (e.g. --env LIST=a,b -> {"key":"LIST","value":"a,b"}). Blank lines skipped.
nv::envs_to_jsonarray() {
  local arr='[]' pair k v
  while IFS= read -r pair; do
    [[ -z "$pair" ]] && continue
    k="${pair%%=*}"
    v="${pair#*=}"
    # A `--env =value` pair yields an empty key; reject it rather than emitting
    # an entry the API would reject cryptically.
    [[ -n "$k" ]] || nv::usage "usage: invalid --env pair (missing key): '$pair'"
    arr="$(jq -c -n --argjson cur "$arr" --arg k "$k" --arg v "$v" '$cur + [{key: $k, value: $v}]')"
  done <<<"$1"
  printf '%s' "$arr"
}

# v2 ports: newline-delimited entries -> numbers or [{port,protocol}] objects.
# An entry is a bare port ("8080") or port:protocol ("8080:tcp"); protocol is
# validated against the API's tcp|http|https set (case-insensitive, uppercased
# is NOT sent — the API takes lowercase). Bare ports stay bare numbers, so the
# body matches the documented endpoint-create example.
nv::ports_to_jsonarray() {
  local arr='[]' entry port proto
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    port="${entry%%:*}"
    proto="${entry#*:}"
    [[ "$port" =~ ^[0-9]+$ ]] || nv::usage "usage: invalid --port '$entry' (expected <port> or <port>:<tcp|http|https>)"
    if [[ "$proto" == "$entry" ]]; then
      proto=""
    fi
    if [[ -n "$proto" ]]; then
      case "$proto" in
      tcp | http | https) ;;
      *) nv::usage "usage: invalid --port protocol '$proto' (expected tcp|http|https)" ;;
      esac
      arr="$(jq -c -n --argjson cur "$arr" --argjson port "$port" --arg proto "$proto" '$cur + [{port: $port, protocol: $proto}]')"
    else
      arr="$(jq -c -n --argjson cur "$arr" --argjson port "$port" '$cur + [$port]')"
    fi
  done <<<"$1"
  printf '%s' "$arr"
}

# v2 INSTANCE ports: the instance-create spec wants objects {port, protocol}
# with BOTH keys required and protocol limited to tcp|http (no https). A bare
# entry ("8080") defaults protocol to tcp. Entries are "<port>" or
# "<port>:<tcp|http>". Used by pod create; endpoints take integers instead
# (see nv::ports_to_jsonarray until the endpoint builder lands).
nv::ports_obj_to_jsonarray() {
  local arr='[]' entry port proto
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    port="${entry%%:*}"
    proto="${entry#*:}"
    # Leading zeros ("0808") would reach jq --argjson as invalid JSON; reject
    # them here so the failure is the intended usage message.
    [[ "$port" =~ ^[1-9][0-9]*$ ]] || nv::usage "usage: invalid --port '$entry' (expected <port> or <port>:<tcp|http>)"
    [[ "$proto" == "$entry" ]] && proto=""
    case "$proto" in
    "") proto="tcp" ;;
    tcp | http) ;;
    *) nv::usage "usage: invalid --port protocol '$proto' (expected tcp|http)" ;;
    esac
    arr="$(jq -c -n --argjson cur "$arr" --argjson port "$port" --arg proto "$proto" '$cur + [{port: $port, protocol: $proto}]')"
  done <<<"$1"
  printf '%s' "$arr"
}

# v2 ENDPOINT ports: the endpoint-create spec wants a plain array of INTEGERS
# ([1,65535], example [8080]) — a "port:proto" suffix is invalid here and is
# rejected with a usage error, as are non-numeric and leading-zero ports.
nv::ports_int_to_jsonarray() {
  local arr='[]' entry port
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    port="${entry%%:*}"
    [[ "$entry" == "$port" ]] || nv::usage "usage: invalid --port '$entry' (endpoints take a bare port number — no ':protocol' suffix)"
    [[ "$port" =~ ^[1-9][0-9]*$ ]] || nv::usage "usage: invalid --port '$entry' (expected a port number, 1-65535)"
    ((port <= 65535)) || nv::usage "usage: invalid --port '$entry' (expected a port number, 1-65535)"
    arr="$(jq -c -n --argjson cur "$arr" --argjson port "$port" '$cur + [$port]')"
  done <<<"$1"
  printf '%s' "$arr"
}

# v2 network-volume mount: {"type":"network","id":ID,"mount_point":PATH}.
# Entries are "<id>:<path>"; the mount point defaults to
# $NV_DEFAULT_MOUNT_POINT (/data). Used by pod and endpoint volume mounts.
nv::volume_mounts_to_jsonarray() {
  local arr='[]' entry id path
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    id="${entry%%:*}"
    path="${entry#*:}"
    [[ "$path" == "$entry" ]] && path="$NV_DEFAULT_MOUNT_POINT"
    [[ -n "$id" ]] || nv::usage "usage: invalid --volume '$entry' (expected <storage-id>:<mount-point>)"
    arr="$(jq -c -n --argjson cur "$arr" --arg id "$id" --arg path "$path" \
      '$cur + [{type: "network", id: $id, mount_point: $path}]')"
  done <<<"$1"
  printf '%s' "$arr"
}

# v2 candidate_regions: a plain array of region-id strings.
nv::regions_to_jsonarray() {
  nv::csv_to_jsonarray "$1"
}

# v2 worker_config: omitting any unset field (the API applies its own defaults).
# Arguments:
#   $1 - min_replicas (int>=0)
#   $2 - max_replicas (int>=0)
#   $3 - idle_timeout (seconds)
#   $4 - max_concurrent_per_worker
#   $5 - gpu_num
#   $6 - rootfs_size_gb
#   $7 - request_timeout (seconds)
nv::json_worker_config() {
  local obj='{}'
  nv::obj_set obj min_replicas "$1"
  nv::obj_set obj max_replicas "$2"
  nv::obj_set obj idle_timeout "$3"
  nv::obj_set obj max_concurrent_per_worker "$4"
  nv::obj_set obj gpu_num "$5"
  nv::obj_set obj rootfs_size_gb "$6"
  nv::obj_set obj request_timeout "$7"
  printf '%s' "$obj"
}

# v2 health_check: {"path": P, "port": N}; either field may be unset.
nv::json_health_check() {
  local obj='{}'
  [[ -n "$1" ]] && nv::obj_set obj path "$(nv::json_str "$1")"
  nv::obj_set obj port "$2"
  printf '%s' "$obj"
}

# v2 scale policy: {"type": queue|concurrency, "value": N}. `queue` measures
# queue wait time; `concurrency` measures in-flight request count.
nv::json_policy() {
  local ptype="$1" value="$2"
  case "$ptype" in
  queue | concurrency) ;;
  *) nv::usage "unknown policy type: '$ptype' (expected queue|concurrency)" ;;
  esac
  nv::json_obj type "$(nv::json_str "$ptype")" value "$value"
}
