#!/usr/bin/env bash
# Credential resolution — the single seam that knows where the Novita API key
# comes from. The transport (lib/transport.sh) calls nv::auth_header and never
# reads NOVITA_API_KEY itself, so the key source is swappable without touching
# curl. Two adapters today, both resolving to a bare key on stdout:
#   - NOVITA_API_KEY        (env var)
#   - NOVITA_API_KEY_FILE   (a file holding the key, e.g. a mounted K8s secret)
# Add a third (keychain, 1Password, SSO) by extending nv::auth_token alone.
[[ -n "${_NV_AUTH:-}" ]] && return 0
_NV_AUTH=1

# Resolve the account name to use, in priority order:
#   --account flag / NV_ACCOUNT env > active pointer > "default" file >
#   the single account file present (if exactly one) > none.
nv::_account_name() {
  local name
  name="${NV_ACCOUNT:-}"
  if [[ -z "$name" && -n "${NV_ARGS[*]:-}" ]]; then
    name="$(nv::args_get account 2>/dev/null)"
  fi
  [[ -n "$name" ]] && {
    printf '%s' "$name"
    return 0
  }
  [[ -f "$NV_ACTIVE_FILE" ]] && {
    cat "$NV_ACTIVE_FILE"
    return 0
  }
  [[ -f "$NV_CREDS_DIR/default" ]] && {
    printf 'default'
    return 0
  }
  local -a names=()
  if [[ -d "$NV_CREDS_DIR" ]]; then
    local f
    for f in "$NV_CREDS_DIR"/*; do
      [[ -f "$f" ]] || continue
      names+=("$(basename "$f")")
    done
  fi
  ((${#names[@]} == 1)) && {
    printf '%s' "${names[0]}"
    return 0
  }
  return 1
}

# Load the resolved account's file into the environment. Explicit exported
# credentials always win; anything nv loaded from a file (legacy .env, install
# .env) may be overridden by a selected account. No-op when nothing resolves.
nv::_load_account() {
  if [[ -n "${NOVITA_API_KEY:-}" || -n "${NOVITA_API_KEY_FILE:-}" ]]; then
    [[ -z "${NV_ENV_SRC[NOVITA_API_KEY]:-}${NV_ENV_SRC[NOVITA_API_KEY_FILE]:-}" ]] && return 0
  fi
  local name file
  name="$(nv::_account_name)" || return 0
  file="$NV_CREDS_DIR/$name"
  [[ -f "$file" ]] || return 0
  # Force-load so the selected account overrides any lower-priority source
  # already in the environment (e.g. the install-local .env loaded at startup).
  _nv_env_load "$file" force
}

# Resolve the API key from the configured source; print it on stdout. Dies
# (exit 3) if neither source is set. The caller must keep it off argv — pipe it
# to a header file via nv::auth_header, never interpolate it into a command line.
#
# Resolution order (highest priority first):
#   1. NOVITA_API_KEY / NOVITA_API_KEY_FILE already in the environment (explicit)
#   2. the selected account file (credentials.d/<name>, via `nv::_load_account`:
#      --account flag / NV_ACCOUNT env / active pointer / "default" / the single
#      account present)
#   3. the legacy per-user .env ($NV_CONFIG_HOME/.env)
#   4. the install-local .env ($NV_ROOT/.env)
nv::auth_token() {
  # Keep the key off `set -x` (bash -x) traces as well as off curl's argv:
  # save xtrace state, silence it for the duration, and restore it on return.
  local _nv_xtrace
  _nv_xtrace="$(nv::_xtrace_save)"
  set +x
  # Honour a selected account (or the active pointer) before reading env.
  nv::_load_account 2>/dev/null || true
  if [[ -n "${NOVITA_API_KEY:-}" ]]; then
    printf '%s' "$NOVITA_API_KEY"
  elif [[ -n "${NOVITA_API_KEY_FILE:-}" ]]; then
    [[ -f "$NOVITA_API_KEY_FILE" ]] || nv::die "NOVITA_API_KEY_FILE points to a missing file: $NOVITA_API_KEY_FILE"
    # Trim a trailing newline so the Bearer value is exact (files end in \n).
    printf '%s' "$(tr -d '\n' <"$NOVITA_API_KEY_FILE")"
  else
    _auth "NOVITA_API_KEY unset — run 'nv auth login', or set NOVITA_API_KEY / NOVITA_API_KEY_FILE"
  fi
  nv::_xtrace_restore "$_nv_xtrace"
}

# Print the full Authorization header line for curl's -H @"file" consumption.
# The key crosses a pipe (not argv), so it never appears in `ps`. xtrace is
# silenced around the build so `set -x` never prints the key in the trace.
nv::auth_header() {
  local _nv_xtrace
  _nv_xtrace="$(nv::_xtrace_save)"
  set +x
  printf 'Authorization: Bearer %s\n' "$(nv::auth_token)"
  nv::_xtrace_restore "$_nv_xtrace"
}
