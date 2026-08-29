#!/usr/bin/env bash
# Flag and positional parser. Every command calls nv::args_parse, then reads values via nv::args_get / _has / _pos / _get_uint / nv::require_pos.
[[ -n "${_NV_ARGS:-}" ]] && return 0
_NV_ARGS=1

declare -gA NV_ARGS=()
# All positional arguments in order (NV_ARGS[pos] is a backward-compat alias for
# the first). A handful of verbs (e.g. `nv serverless run <id> --input …`) take
# more than one positional; read the rest via nv::args_pos_at / nv::require_pos_at.
declare -ga NV_POSITIONALS=()
NV_BOOL_FLAGS=(json help force insecure sync jupyter)
# Value flags that may be repeated; occurrences accumulate newline-joined, so
# `--env A=1 --env B=2` becomes "A=1\nB=2". Newline (not comma) is the separator
# so a single value may itself contain commas (e.g. --env LIST=a,b). Add a flag
# name here to make it repeatable; consumers iterate the joined value by line
# (nv::envs_to_jsonarray).
NV_REPEAT_FLAGS=(env volume port region)

_nv_args_is_repeatable() {
  [[ " ${NV_REPEAT_FLAGS[*]} " == *" $1 "* ]]
}

nv::args_parse() {
  NV_ARGS=()
  local k
  while (($#)); do
    case "$1" in
    --help | -h)
      NV_ARGS[help]=1
      shift
      ;;
    -k)
      # Short alias for --insecure: skip TLS certificate verification, e.g. when
      # nv runs from inside an instance whose CA bundle can't validate the API.
      NV_ARGS[insecure]=1
      shift
      ;;
    --*=*)
      k="${1%%=*}"
      k="${k#--}"
      if _nv_args_is_repeatable "$k"; then
        NV_ARGS["$k"]="${NV_ARGS[$k]:+${NV_ARGS[$k]}$'\n'}${1#*=}"
      else
        NV_ARGS["$k"]="${1#*=}"
      fi
      shift
      ;;
    --*)
      k="${1#--}"
      shift
      if [[ " ${NV_BOOL_FLAGS[*]} " == *" $k "* ]]; then
        NV_ARGS["$k"]=1
      elif _nv_args_is_repeatable "$k"; then
        (($#)) || nv::usage "flag --$k requires a value"
        NV_ARGS["$k"]="${NV_ARGS[$k]:+${NV_ARGS[$k]}$'\n'}$1"
        shift
      else
        (($#)) || nv::usage "flag --$k requires a value"
        NV_ARGS["$k"]="$1"
        shift
      fi
      ;;
    *)
      # Collect every positional in order; NV_ARGS[pos] stays the first for the
      # many verbs that take exactly one id (e.g. `nv pod get <id>`). Verbs that
      # need more read the rest via nv::args_pos_at / nv::require_pos_at.
      NV_POSITIONALS+=("$1")
      [[ -n "${NV_ARGS[pos]:-}" ]] || NV_ARGS[pos]="$1"
      shift
      ;;
    esac
  done
  nv::args_apply_aliases
}

nv::args_get() { printf '%s' "${NV_ARGS[$1]:-${2:-}}"; }

nv::args_has() { [[ -n "${NV_ARGS[$1]:-}" ]]; }

nv::args_pos() { printf '%s' "${NV_ARGS[pos]:-}"; }

# Print the positional at index $1 (0-based). Defaults to the first when $1 is
# empty. Used by verbs with more than one positional.
nv::args_pos_at() {
  local idx="${1:-0}"
  printf '%s' "${NV_POSITIONALS[$idx]:-}"
}

# Assign the positional to the variable named in $1.
# Arguments:
#   $1 - out: caller's variable name (nameref) to receive the positional
#   $2 - usage: message shown when none was given
# Returns:
#   0 - positional assigned to $1
#   1 - no positional given (nv::usage)
# Runs in the main shell, not via command substitution, so the exit fires even
# when the caller has errexit off.
nv::require_pos() {
  local -n require_pos_out="$1"
  [[ -n "${NV_ARGS[pos]:-}" ]] || nv::usage "$2"
  # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
  require_pos_out="${NV_ARGS[pos]}"
}

# Like nv::require_pos but for the positional at index $1 (0-based). Lets a verb
# demand a specific positional beyond the first.
# Arguments:
#   $1 - index: 0-based positional index
#   $2 - out: caller's variable name (nameref) to receive the positional
#   $3 - usage: message shown when the positional is missing
nv::require_pos_at() {
  local idx="${1:-0}"
  local -n require_pos_at_out="$2"
  [[ -n "${NV_POSITIONALS[$idx]:-}" ]] || nv::usage "$3"
  # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
  require_pos_at_out="${NV_POSITIONALS[$idx]}"
}

# nv::args_get that nv::die's unless the value is a non-negative integer (or unset).
nv::args_get_uint() {
  local val
  val="$(nv::args_get "$1" "${2:-}")"
  nv::require_uint "$val" "$1"
  printf '%s' "$val"
}

# Assign the true|false value of --$2 to the variable named by $1 (nameref);
# empty when the flag is unset, nv::usage on any other token. For value flags
# that must carry both directions (--auto-migrate, --auto-renew) so update can
# DISABLE as well as enable — a bare bool flag can only express true.
# Call DIRECTLY, never inside command substitution: nv::usage's exit must fire in
# the caller's shell, and tests run with errexit off (so `v="$(nv::… F)"` would
# swallow a bad token). Mirrors nv::require_pos.
nv::require_bool() {
  local -n require_bool_out="$1"
  require_bool_out="$(nv::args_get "$2" "${3:-}")"
  case "$require_bool_out" in
  '') ;;
  true | false) ;;
  *) nv::usage "invalid --$2 '$require_bool_out' (expected true|false)" ;;
  esac
}

nv::split_csv() {
  local -a arr
  IFS=, read -ra arr <<<"$1"
  printf '%s\n' "${arr[@]}"
}

# Post-parse flag aliases: verbose API spelling -> nv canonical (key-copy only).
# Never overloads an nv flag, and never overwrites an explicitly-set canonical
# value. --env is deliberately a first-class repeat flag, not an alias.
NV_FLAG_ALIASES=(
  "product-id:product"
  "region-id:region"
  "candidate-regions:region"
  "registry-auth-id:registry"
  "rootfs-size-gb:rootfs-gb"
  "gpu-num:gpu-count"
  "mount-point:mount"
  "storage-size:size"
  "storage-name:name"
  "cluster-id:cluster"
  "app-name:app"
)

# An alias whose name already means something in nv (a known bool/repeat flag)
# is skipped — nv's meaning always wins, never overloaded.
# Returns 0 (free) when $1 is not a known bool/repeat flag, 1 otherwise.
nv::args_alias_is_free() {
  [[ " ${NV_BOOL_FLAGS[*]} ${NV_REPEAT_FLAGS[*]} " != *" $1 "* ]]
}

# Apply NV_FLAG_ALIASES once after parsing: copy each alias into its canonical
# when the canonical is absent (rp's fill-gap semantics — the canonical always
# wins, the alias never overwrites it). Called from nv::args_parse; the
# tokenizer above is untouched.
nv::args_apply_aliases() {
  local entry alias canonical
  for entry in "${NV_FLAG_ALIASES[@]}"; do
    alias="${entry%%:*}"
    canonical="${entry##*:}"
    nv::args_alias_is_free "$alias" || continue
    if [[ -z "${NV_ARGS[$canonical]:-}" && -n "${NV_ARGS[$alias]:-}" ]]; then
      NV_ARGS["$canonical"]="${NV_ARGS[$alias]}"
    fi
  done
}
