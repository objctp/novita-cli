#!/usr/bin/env bash
# Shared runtime: coloured output helpers, verb output policy (nv::emit_json_or),
# distinct-code exiters, temp-file cleanup, and the core-tool check. Sourced
# first by bin/nv.
[[ -n "${_NV_COMMON:-}" ]] && return 0
_NV_COMMON=1

# Per-credential source tracking (file path) for `nv auth status`. Always
# declared here (not just in bin/nv) so it exists even when common.sh is sourced
# directly by unit tests under `set -u`. bin/nv populates it while loading .env.
# shellcheck disable=SC2034 # populated by bin/nv's _nv_env_load + consumed by nv auth status
declare -gA NV_ENV_SRC=()

NV_ROOT="${NV_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)}"
# Tunable defaults / magic values (timeouts, size defaults) live in
# lib/constants.sh. Sourced here so every consumer — including the test harnesses
# that source common.sh directly — has them without a separate include.
. "$NV_ROOT/lib/constants.sh"
# One host, two API namespaces (https://api.novita.ai):
#   v2 — /gpus/v2/...        snake_case bodies (instances, endpoints, products,
#                            templates, regions) with cursor pagination
#   v1 — /gpu-instance/openapi/v1/...  camelCase bodies (clusters, network
#                            storage, repository auths) with pageNo pagination
# Override to pin a staging host. Route by resource, not by a single "plane".
NV_BASE_V2="${NV_BASE_V2:-https://api.novita.ai/gpus/v2}"
NV_BASE_V1="${NV_BASE_V1:-https://api.novita.ai/gpu-instance/openapi/v1}"

# Distinct exit codes so `nv` is scriptable without parsing stderr:
#   1 general/transport/API error · 2 usage · 3 auth · 4 not-found
# HTTP status -> exit code (see nv::http_exit_code):
#   401/403 rejected API key -> 3 · 404 unknown resource/id -> 4 · other >=400 -> 1
NV_EXIT_USAGE=2
NV_EXIT_AUTH=3
NV_EXIT_NOTFOUND=4

# Map an HTTP status to this CLI's exit code per the documented contract, so a
# script can branch on the code without parsing stderr:
#   401/403 rejected API key -> NV_EXIT_AUTH (3)
#   404 unknown resource / id -> NV_EXIT_NOTFOUND (4)
#   any other >= 400          -> 1 (general API error)
#   < 400                     -> 0 (success; handled by the caller)
# Pure (no exit) so it is unit-testable in isolation.
nv::http_exit_code() {
  local status="$1"
  if ((status == 401 || status == 403)); then
    printf '%s' "$NV_EXIT_AUTH"
  elif ((status == 404)); then
    printf '%s' "$NV_EXIT_NOTFOUND"
  elif ((status >= 400)); then
    printf '%s' 1
  else
    printf '%s' 0
  fi
}

# Apply the exit-code contract to an HTTP error: 404 -> not-found (4),
# 401/403 rejected key -> auth (3), any other >= 400 -> general error (1).
# Exit policy only — the caller builds the human-facing $2 message. Centralised
# so the buffered HTTP emit sites don't each re-derive the mapping.
_nv_exit_for_status() {
  local status="$1" err="$2"
  local code
  code="$(nv::http_exit_code "$status")"
  if ((code == NV_EXIT_NOTFOUND)); then
    nv::notfound "$err"
  elif ((code == NV_EXIT_AUTH)); then
    _auth "$err"
  else
    nv::die "$err"
  fi
}

if [[ -t 2 ]]; then
  NV_C_RED=$'\033[31m'
  NV_C_YEL=$'\033[33m'
  NV_C_GRN=$'\033[32m'
  NV_C_RST=$'\033[0m'
else
  NV_C_RED=''
  NV_C_YEL=''
  NV_C_GRN=''
  NV_C_RST=''
fi

###
### :::: temp files & startup checks :::: ######################################
###

# Temp paths registered for removal on exit or interruption.
_NV_TEMPS=()

_error() { printf '%s%s%s\n' "$NV_C_RED" "$*" "$NV_C_RST" >&2; }

_auth() {
  _error "$*"
  exit "$NV_EXIT_AUTH"
}

# Remove every registered temp file (idempotent — safe to call from a trap).
_tmp_cleanup() {
  ((${#_NV_TEMPS[@]})) || return 0
  rm -f -- "${_NV_TEMPS[@]}"
  _NV_TEMPS=()
}

# Create a temp file, register it for the cleanup trap, and assign its path to
# the nameref named in $1. Callers MUST pass a variable name (`_mktemp tmp`),
# not command substitution (`x=$(_mktemp)`) — `$()` runs in a subshell, which
# would silently discard the registration (and the INT/TERM trap that depends
# on it). Because bin/nv's INT/TERM trap is inherited, each `$()` subshell cleans
# its own temps; the main-process EXIT trap cleans the rest.
_mktemp() {
  local -n mktemp_out="$1"
  mktemp_out="$(mktemp)" || return 1
  _NV_TEMPS+=("$mktemp_out")
}

# Warn (stderr) if $1 is readable by group or other — guards credential files
# like .env. Portable across macOS (stat -f) and Linux (stat -c). Must return 0
# in the private case too: callers run it bare under `set -e`, so a non-zero
# return here would abort nv whenever .env is correctly locked down (mode 600).
_warn_if_world_readable() {
  local f="$1" perm
  # Probe for the BSD (macOS) stat dialect first. GNU stat accepts -f but uses it
  # for filesystem output and still emits to stdout on a bad directive, so a
  # `stat -f … || stat -c …` chain would concatenate that junk with the fallback
  # and leave $perm non-numeric — which would silently skip the check on Linux.
  if stat -f '%Lp' /dev/null >/dev/null 2>&1; then
    perm="$(stat -f '%Lp' "$f")"
  else
    perm="$(stat -c '%a' "$f")"
  fi
  [[ "$perm" =~ ^[0-7]+$ ]] || return 0
  if ((8#$perm & 077)); then
    nv::warn "note: $f is group/world-readable (mode $perm); tighten with 'chmod 600 $f' — it holds your API key"
  fi
}

nv::info() { printf '%s\n' "$*" >&2; }

nv::warn() { printf '%s%s%s\n' "$NV_C_YEL" "$*" "$NV_C_RST" >&2; }

nv::ok() { printf '%s%s%s\n' "$NV_C_GRN" "$*" "$NV_C_RST" >&2; }

nv::die() {
  _error "$*"
  exit 1
}

# Specialised exiters: same stderr output as nv::die, distinct exit codes.
nv::usage() {
  _error "$*"
  exit "$NV_EXIT_USAGE"
}

nv::notfound() {
  _error "$*"
  exit "$NV_EXIT_NOTFOUND"
}

nv::require_api_key() {
  # Silence xtrace around the presence check so the token value never lands in
  # a `bash -x` trace (same class of exposure as the auth-header printf).
  local _nv_xtrace
  _nv_xtrace="$(nv::_xtrace_save)"
  set +x
  # Honour a selected account (or the active pointer) before the presence check.
  nv::_load_account 2>/dev/null || true
  [[ -n "${NOVITA_API_KEY:-}" || -n "${NOVITA_API_KEY_FILE:-}" ]] || _auth "NOVITA_API_KEY unset — run 'nv auth login', or set NOVITA_API_KEY / NOVITA_API_KEY_FILE"
  nv::_xtrace_restore "$_nv_xtrace"
}

nv::require_cmd() {
  command -v "$1" >/dev/null 2>&1 || nv::usage "required command not found: $1"
}

# Save/restore the current xtrace state so a secret can be handled without it
# leaking into a `bash -x` trace. Centralised here so the suppress-xtrace idiom
# isn't copy-pasted (and drifted) across every token-touching function.
nv::_xtrace_save() { shopt -po xtrace 2>/dev/null || true; }
nv::_xtrace_restore() { eval "$1" 2>/dev/null || true; }

# Die unless $2 is a well-formed resource/object id before it is interpolated
# into a REST path. Novita ids are UUIDs or alphanumeric tokens; the guard also
# admits `.` and `-` and rejects path/query metacharacters (`/`, `?`, `&`) and
# whitespace, so a crafted id can neither split the path nor inject a query
# string. $3 is the noun for the error message (e.g. "instance id").
nv::require_id() {
  local -n require_id_out="$1"
  local val="$2" label="$3"
  [[ "$val" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] ||
    nv::usage "usage: invalid $label '$val' (ids are letters, digits, . and - only)"
  # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
  require_id_out="$val"
}

# Extract the new record's id from a create response body, or die with a clear
# error. Novita's create responses vary by namespace: v2 instance/endpoint
# creates answer {"id": "..."}, v2 template create/update answer
# {"template_id": "..."}, whilst the v1 network-storage create answers a BARE
# JSON STRING ("storage-id"). All three forms are handled here.
# Arguments:
#   $1 - out: caller's variable name (nameref) to receive the id
#   $2 - body: the JSON response body
#   $3 - label: noun for the error message (e.g. "volume")
# Returns:
#   0 - id extracted into $1
#   1 - no id present in body (dies via nv::die)
# Must run in the main shell so the nv::die exit propagates — unlike
# `$(nv::extract_id …)`, which would swallow it inside a command substitution.
nv::extract_id() {
  local -n extract_id_out="$1"
  local body="$2" label="$3"
  # A bare string body IS the id (v1 network-storage create); an object's .id
  # or .template_id wins otherwise. `select(.)` keeps empty strings from
  # slipping through.
  extract_id_out="$(printf '%s' "$body" | jq -r 'if type == "string" then . else (.id // .template_id // empty) end' 2>/dev/null)"
  [[ -n "$extract_id_out" ]] || nv::die "$label create returned no id: $body"
}

# Die unless $1 is a non-negative integer (empty is allowed — means unset). $2
# is the flag name for the message. Guards numeric flags so a typo yields a clear
# error instead of an opaque jq/arithmetic failure downstream.
nv::require_uint() {
  local val="$1" name="$2"
  [[ -z "$val" || "$val" =~ ^[0-9]+$ ]] || nv::usage "--$name must be a positive integer (got '$val')"
}

# Scan the named commands; if any are absent, die via nv::usage (exit 2) naming
# them. Shared by the runtime and core preflights so the missing-command detect
# loop lives in one place. Returns 0 when all are present.
_nv_require_commands() {
  local missing=() c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  ((${#missing[@]})) || return 0
  nv::usage "missing required commands: ${missing[*]} (install via your package manager)"
}

# Hard runtime preflight — runs before any work. nv itself needs Bash 5+
# (namerefs, assoc arrays, mapfile); every code path depends on jq (JSON) and
# curl (transport). Die with a message naming the missing piece rather than
# failing later with an opaque "command not found".
nv::check_runtime() {
  if ((BASH_VERSINFO[0] < 5)); then
    nv::die "nv needs Bash 5+ (this is Bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]:-?}); upgrade Bash and retry"
  fi
  _nv_require_commands jq curl
}

# Fail fast if a core tool the CLI depends on is missing.
nv::check_core() {
  _nv_require_commands jq curl awk head paste
}

# Verb output policy: with --json print $1 verbatim (raw API JSON); otherwise
# run the remaining args as the human-mode formatter command. Single-line human
# paths inline their command (nv::ok / nv::table / nv::json_pretty); multi-line
# formatters live in named _<cmd>_<verb>_human functions in the command module.
nv::emit_json_or() {
  local json="$1"
  shift
  if nv::args_has json; then
    printf '%s\n' "$json"
    return 0
  fi
  "$@"
}

# Column-aligned table renderer. Pure jq (no column(1)) so output is portable
# across macOS/Linux/BSD. Numeric columns right-align; on a TTY with NO_COLOR
# unset the header is bold and status tokens are tinted. --json is handled
# upstream by nv::emit_json_or, not here.
# Arguments:
#   $1      - json: payload to table (array, or object wrapping one)
#   $2..    - columns: column names to extract in order; missing values render empty
#   --reshape <jq>  remap the payload before tabling (rename / nest / coerce / sort)
#   --color         force ANSI colour on
#   --no-color      force ANSI colour off
# Returns:
#   0 - always (a null payload prints the header row alone)
#   1 - malformed --reshape filter (fails loud rather than a blank table)
nv::table() {
  local json="$1"
  shift
  local reshape='.' color_mode=auto
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
    --reshape)
      reshape="$2"
      shift 2
      ;;
    --color)
      color_mode=on
      shift
      ;;
    --no-color)
      color_mode=off
      shift
      ;;
    *) break ;;
    esac
  done
  local cols=("$@")

  local body
  body="$(printf '%s' "$json" | jq -c 'if . == null then [] else . end' | jq -c "$reshape")" || return 1

  # Colour gate: on for a TTY stdout unless NO_COLOR is set, or forced via flags.
  local c_on=0
  case "$color_mode" in
  on) c_on=1 ;;
  off) c_on=0 ;;
  *) [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && c_on=1 ;;
  esac
  local c_bold='' c_red='' c_grn='' c_yel='' c_rst=''
  if ((c_on)); then
    c_bold=$'\033[1m'
    c_red=$'\033[31m'
    c_grn=$'\033[32m'
    c_yel=$'\033[33m'
    c_rst=$'\033[0m'
  fi

  # Inlined `jq -R . | jq -sc .` (rather than nv::json_array) to keep common.sh
  # free of a dependency on lib/json.sh; this is the lowest-level renderer.
  printf '%s' "$body" | jq -r --argjson fields "$(printf '%s\n' "${cols[@]}" | jq -R . | jq -sc .)" \
    --arg c_bold "$c_bold" --arg c_red "$c_red" --arg c_grn "$c_grn" --arg c_yel "$c_yel" --arg c_rst "$c_rst" '
  def colorize($col; $v):
    if ($v == "exited" or $v == "error" or $v == "failed" or $v == "unhealthy" or $v == "DEPLETED") then $c_red + $v + $c_rst
    elif ($v == "running" or $v == "healthy" or $v == "active" or $v == "created" or $v == "yes") then $c_grn + $v + $c_rst
    elif ($v == "creating" or $v == "starting" or $v == "stopping" or $v == "warning") then $c_yel + $v + $c_rst
    else $v end;
  (if . == null then [] else . end) as $data
  | ($fields | map(tostring)) as $heads
  | ($data | map([ $fields[] as $f | ((.[$f] // "") | tostring) ])) as $rows
  | ($heads | length) as $n
  | [ range(0;$n) ] as $ci
  # Column width = widest of the header cell and the values beneath it.
  | ($ci | map(. as $c | ([$heads[$c]] + [$rows[][$c]] | map(length) | max // 0))) as $w
  # A column right-aligns only when every non-empty value parses as a number.
  | ($ci | map(. as $c | ([$rows[][$c]] | map(select(length > 0)) | if length == 0 then false else all(test("^[-+]?[0-9]+(\\.[0-9]+)?$")) end))) as $num
  | (($ci | map(. as $c | ($c_bold + $heads[$c] + $c_rst) + (" " * (($w[$c]) - ($heads[$c] | length))))) | join("  ") | sub(" +$"; ""))
  , ($rows | map(. as $r | ($ci | map(. as $c | ($r[$c]) as $v | (($w[$c]) - ($v | length)) as $pad | if $num[$c] then (" " * $pad) + colorize($heads[$c]; $v) else colorize($heads[$c]; $v) + (" " * $pad) end) | join("  ") | sub(" +$"; ""))))[]'
}

# Unwrap a list response that is wrapped in a single named array key. Novita is
# uniform here: every list across both namespaces answers {"data": [...]} (v2
# envelopes add next_cursor/has_more/total; the v1 storage list adds total), so
# the caller passes "data". When $2 is omitted or "-", read the JSON from stdin.
# Arrays and bare objects pass through unchanged, so single GET/POST/DELETE
# responses (object or empty) are unaffected.
nv::unwrap() {
  local key="$1" json="${2:-}"
  [[ -n "$json" && "$json" != "-" ]] || json="$(cat)"
  printf '%s' "$json" | jq -c --arg k "$key" '
    if type == "array" then .
    elif type == "object" and (has($k) and (.[$k] | type) == "array") then .[$k]
    else . end'
}
