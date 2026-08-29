#!/usr/bin/env bash
#
# Manage Novita API credentials in a stable per-user store.
# This store survives any install method — including an npm global install
# whose files live inside node_modules and are wiped on every `npm upgrade`.
# One key per account, exactly one "active" account used for API calls,
# switchable with `nv auth switch`.
#
# Layout under $NV_CONFIG_HOME:
#   credentials.d/<name>   one account: NOVITA_API_KEY
#   active                 a file containing the name of the active account
#
# There is no OAuth/browser login — Novita is API-key only, so `login` just
# captures and stores the key you copy from novita.ai account settings.
#
# Usage: nv auth <verb> [flags]
#

# The credential keys `nv auth` manages in each account file. Stored unquoted
# (no surrounding quotes) so the loader re-reads them verbatim.
_AUTH_KEYS='^(NOVITA_API_KEY|NOVITA_API_KEY_FILE)='

# Mask a key for display: keep the first 3 and last 4 chars, elide the middle;
# short keys (<8 chars) are fully redacted.
_auth_mask() {
  local v="$1" len=${#1}
  if ((len < 8)); then
    printf '%s' "${v//?/*}"
  else
    printf '%s…%s' "${v:0:3}" "${v: -4}"
  fi
}

# Report where $1's value came from: an explicit export (no tracked source), the
# user config ($NV_CONFIG_HOME/.env), the install .env, or an account file.
_auth_source() {
  local src="${NV_ENV_SRC[$1]:-}"
  [[ -z "$src" ]] && {
    printf 'environment (exported)'
    return
  }
  [[ "$src" == "$NV_CONFIG_HOME/.env" ]] && {
    printf 'user config (%s)' "$src"
    return
  }
  [[ "$src" == "$NV_ROOT/.env" ]] && {
    printf 'install .env (%s)' "$src"
    return
  }
  [[ "$src" == "$NV_CREDS_DIR"/* ]] && {
    printf 'account file (%s)' "$src"
    return
  }
  printf '%s' "$src"
}

# List stored account names (one per line), empty if none.
_auth_accounts() {
  [[ -d "$NV_CREDS_DIR" ]] || return 0
  local f
  for f in "$NV_CREDS_DIR"/*; do
    [[ -f "$f" ]] || continue
    basename "$f"
  done
}

_auth_active_name() {
  [[ -f "$NV_ACTIVE_FILE" ]] && cat "$NV_ACTIVE_FILE"
}

# Read a single KEY=VALUE from a credentials file; empty if absent.
_auth_read_key() {
  local f="$1" key="$2" line
  [[ -f "$f" ]] || return 0
  line="$(grep -E "^${key}=" "$f" 2>/dev/null | tail -1)"
  [[ -z "$line" ]] && return 0
  printf '%s' "${line#*=}"
}

# Write one account file, preserving any non-credential lines already there, with
# the dir at 700 and the file at 600.
_auth_write_account() {
  local name="$1" ak="$2" akf="$3"
  local dir="$NV_CREDS_DIR" file tmp
  file="$dir/$name"
  mkdir -p "$dir"
  chmod 700 "$NV_CONFIG_HOME"
  chmod 700 "$dir"
  tmp="$(mktemp)"
  : >"$tmp"
  # Preserve any non-auth lines (user comments or other vars). `grep -vE`
  # exits 1 when it matches nothing, which would trip `set -e` and abort the
  # whole write — so guard with `|| true`.
  if [[ -f "$file" ]]; then
    grep -vE "$_AUTH_KEYS" "$file" >>"$tmp" 2>/dev/null || true
  fi
  # Merge: keep an existing value when the caller didn't supply one, so a
  # partial login preserves keys set in a previous call instead of wiping them.
  if [[ -f "$file" ]]; then
    [[ -z "$ak" ]] && ak="$(_auth_read_key "$file" NOVITA_API_KEY)"
    [[ -z "$akf" ]] && akf="$(_auth_read_key "$file" NOVITA_API_KEY_FILE)"
  fi
  [[ -n "$ak" ]] && printf 'NOVITA_API_KEY=%s\n' "$ak" >>"$tmp"
  [[ -n "$akf" ]] && printf 'NOVITA_API_KEY_FILE=%s\n' "$akf" >>"$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

_auth_set_active() {
  printf '%s' "$1" >"$NV_ACTIVE_FILE"
  chmod 600 "$NV_ACTIVE_FILE"
}

_auth_login() {
  local name api_key api_key_file
  name="$(nv::args_get name)"
  [[ -z "$name" ]] && name=default
  api_key="$(nv::args_get api-key)"
  api_key_file="$(nv::args_get key-file)"
  # Interactive capture when no key is set yet and we have a terminal.
  if [[ -z "$api_key" && -z "$api_key_file" && -t 0 ]]; then
    read -s -r -p "Novita API key (novita.ai > account settings > API keys): " api_key
    printf '\n' >/dev/tty
  elif [[ -z "$api_key" && -z "$api_key_file" && ! -t 0 ]]; then
    # Piped, no flags: take the API key from the first stdin line.
    IFS= read -r api_key
  fi
  [[ -z "$api_key" && -z "$api_key_file" ]] &&
    nv::usage "no credentials given — pass --api-key, --key-file, or run interactively at a terminal"
  _auth_write_account "$name" "$api_key" "$api_key_file"
  _auth_set_active "$name"
  nv::ok "stored account '$name' in $NV_CREDS_DIR/$name (mode 600); it is now active"
  nv::info "the active account's key loads automatically on every 'nv' call"
}

_auth_logout() {
  local name="${1:-}" active remaining next
  [[ -z "$name" ]] && name="$(_auth_active_name)"
  [[ -z "$name" ]] && {
    nv::info "no active account to log out"
    return 0
  }
  local file="$NV_CREDS_DIR/$name"
  [[ -f "$file" ]] || {
    nv::info "no such account: '$name'"
    return 0
  }
  rm -f "$file"
  nv::ok "removed account '$name'"
  # If the removed account was active and others remain, switch to another.
  active="$(_auth_active_name)"
  if [[ "$active" == "$name" ]]; then
    remaining="$(_auth_accounts)"
    if [[ -n "$remaining" ]]; then
      next="$(printf '%s\n' "$remaining" | head -1)"
      _auth_set_active "$next"
      nv::ok "switched active account to '$next'"
    else
      rm -f "$NV_ACTIVE_FILE"
      nv::info "no accounts remain"
    fi
  fi
}

_auth_switch() {
  local name="${1:-}"
  [[ -z "$name" ]] && nv::usage "usage: nv auth switch <name>   (see: nv auth list)"
  [[ -f "$NV_CREDS_DIR/$name" ]] || nv::die "no such account: '$name' (see: nv auth list)"
  _auth_set_active "$name"
  nv::ok "active account is now '$name'"
}

_auth_list() {
  local active name
  active="$(_auth_active_name)"
  local names
  names="$(_auth_accounts)"
  if [[ -z "$names" ]]; then
    nv::info "no accounts stored (run: nv auth login)"
    return 0
  fi
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ "$name" == "$active" ]]; then
      nv::ok "$name (active)"
    else
      nv::info "$name"
    fi
  done <<<"$names"
}

_auth_status() {
  nv::_load_account 2>/dev/null || true
  local ak="${NOVITA_API_KEY:-}" akf="${NOVITA_API_KEY_FILE:-}"
  local acct
  acct="$(nv::_account_name 2>/dev/null)"
  printf 'ACTIVE ACCOUNT  %s\n' "${acct:-<none>}"
  if [[ -n "$ak" ]]; then
    printf 'API KEY         configured   token %s\n' "$(_auth_mask "$ak")"
    printf '  source:       %s\n' "$(_auth_source NOVITA_API_KEY)"
  elif [[ -n "$akf" ]]; then
    printf 'API KEY         configured   via file %s\n' "$akf"
    printf '  source:       %s\n' "$(_auth_source NOVITA_API_KEY_FILE)"
  else
    printf 'API KEY         NOT configured\n'
  fi
  printf 'CONFIG HOME     %s\n' "$NV_CONFIG_HOME"
}

_auth_help() {
  cat <<'EOF'
Usage: nv auth <verb> [flags]

Manage Novita API credentials in a stable per-user store
(${XDG_CONFIG_HOME:-$HOME/.config}/novita by default) that survives any install
method, including npm global installs. Multiple accounts are supported: each is
a separate file under credentials.d/, with one marked "active" and used for all
API calls. Login is additive, switch changes the active account.

Verbs:
  login     store an account (--name <n>, else "default") and mark it active
  logout    remove an account (--name <n>, else the active one)
  switch    change the active account  (alias: use)
  list      show stored accounts, marking the active one
  status    show the active account and whether a key is configured

login flags:
  --name <n>         account name (default: "default")
  --api-key <k>      API key to store (non-interactive)
  --key-file <path>  store a NOVITA_API_KEY_FILE pointer instead of the key
  (with no flags, prompts interactively, or reads the API key from stdin)

Any command accepts --account <name> to use a specific account for that call
(overrides the active one). An exported NOVITA_API_KEY always wins over all.
EOF
}

###
### :::: documentation (nv doc auth) :::: ######################################
###

# doc: login
# Store a Novita API key as an account (additive — does not replace others).
# Login marks it active; the key then loads automatically on every `nv` call.
#
# Usage: nv auth login [--name <n>] [--api-key <k>] [--key-file <path>]
#
# Options:
#   --name <n>         account name (default: "default")
#   --api-key <k>      API key to store (non-interactive)
#   --key-file <path>  store a NOVITA_API_KEY_FILE pointer instead of the key
#                      itself (useful for mounted secrets)
#
# Notes:
#   With no flags, prompts interactively at a terminal (input hidden), or reads
#   the API key from the first stdin line when piped. Stored unquoted at
#   $NV_CONFIG_HOME/credentials.d/<name> (mode 600, dir 700); other lines there
#   are preserved. The API key is the only auth Novita supports — no OAuth.
#
# doc: logout
# Remove an account.
# If it was active and other accounts remain, the active account switches to one of the others.
#
# Usage: nv auth logout [--name <n>]
#
# doc: switch
# Change the active account — the one used for all API calls.
#
# Usage: nv auth switch <name>   (alias: nv auth use <name>)
#
# doc: use
# Alias for `nv auth switch <name>` — change the active account.
#
# Usage: nv auth use <name>
#
# doc: list
# Show stored accounts, marking the active one.
#
# Usage: nv auth list
#
# doc: status
# Show the active account and whether an API key is configured.
# Reports the effective source (environment export, account file, or user/install .env).
#
# Usage: nv auth status
#
# Notes:
#   The token is masked for display.

nv::cmd_auth() {
  local verb="${1:-help}"
  shift || true
  if [[ "$verb" == "use" ]]; then
    # `nv auth use <name>` is an alias for switch.
    verb=switch
  fi
  nv::args_parse "$@"
  nv::args_has help && verb=help
  case "$verb" in
  login) _auth_login ;;
  logout) _auth_logout "$(nv::args_get name)" ;;
  switch) _auth_switch "${1:-}" ;;
  list) _auth_list ;;
  status) _auth_status ;;
  -h | --help | help) _auth_help ;;
  *) nv::usage "unknown auth verb: '$verb' (try: nv auth --help)" ;;
  esac
}
