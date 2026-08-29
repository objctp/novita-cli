#!/usr/bin/env bash
# install.sh — one-line installer for nv (Novita CLI).
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/novita-cli/main/install.sh | bash
#
# Bash 3.2-safe on purpose. macOS pipes this to /bin/bash (3.2), so the script
# must run under it long enough to print the "nv needs Bash 5+" error: no
# associative arrays, no mapfile/readarray, no ${var,,}. nv itself needs Bash 5+,
# so on macOS we detect an older bash and refuse rather than install something
# that won't run. nv is plain bash, so there is one universal tarball — no
# per-OS/arch matrix.
set -euo pipefail

# OWNER/REPO that hosts releases and this script. Update when the canonical
# repo is pushed (and keep release.yml's npm/package names in step).
NV_REPO="objctp/novita-cli"
NV_INSTALL_DIR="${NV_INSTALL_DIR:-$HOME/.nv}"
NV_BINDIR="${NV_BINDIR:-/usr/local/bin}"

# Temp dir for the install flow. Global (not local to nv_inst_run) so the EXIT
# trap can rm it after the function returns — a `local` would be out of scope by
# then, leaving the temp dir behind and tripping `set -u` in the trap.
_nv_inst_tmp=""

if [[ -t 1 ]]; then
  _C_RED=$'\033[31m'
  _C_GRN=$'\033[32m'
  _C_YEL=$'\033[33m'
  _C_RST=$'\033[0m'
else
  _C_RED=""
  _C_GRN=""
  _C_YEL=""
  _C_RST=""
fi

nv_inst_info() { printf '%s\n' "$*" >&2; }
nv_inst_warn() { printf '%s%s%s\n' "$_C_YEL" "$*" "$_C_RST" >&2; }
nv_inst_ok() { printf '%s%s%s\n' "$_C_GRN" "$*" "$_C_RST" >&2; }
nv_inst_err() { printf '%s%s%s\n' "$_C_RED" "$*" "$_C_RST" >&2; }
nv_inst_die() {
  nv_inst_err "$*"
  exit 1
}

###
### :::: probes :::: ###################
###
# Each probe reads an override env var so the installer is testable.

# Echo darwin/linux; return 1 on anything else.
nv_inst_os() {
  local u="${NV_UNAME:-$(uname -s)}"
  case "$u" in
  Darwin) echo darwin ;;
  Linux) echo linux ;;
  *) return 1 ;;
  esac
}

# Return 0 if the running bash is major >= 5 (nv's requirement). NV_BASH_MAJOR
# lets tests simulate macOS's 3.2 without a readonly BASH_VERSINFO override.
nv_inst_bash_ok() {
  local major="${NV_BASH_MAJOR:-${BASH_VERSINFO[0]:-0}}"
  [[ "$major" -ge 5 ]]
}

# Reject a version/Tag that does not look like a release. A crafted or
# typo'd value would otherwise be interpolated into the GitHub release URL and,
# after curl's path-normalisation, could redirect the download to an
# attacker-controlled repo. Only x.y.z (with an optional leading v) is accepted.
nv_inst_validate_version() {
  [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    nv_inst_die "invalid version '$1' — expected x.y.z or vX.Y.Z (e.g. 1.2.3)"
}

# Echo the release tag to install. NV_LATEST_TAG short-circuits the network
# lookup for tests; otherwise GitHub's /releases/latest 302-redirects to
# /releases/tag/<tag>, and following it to the final URL needs no jq and dodges
# the rate-limited REST API. The resolved tag is validated before use so a
# hostile/malformed redirect cannot steer the install elsewhere.
nv_inst_resolve_version() {
  local tag
  if [[ -n "${NV_LATEST_TAG:-}" ]]; then
    tag="$NV_LATEST_TAG"
  else
    local url
    url="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
      "https://github.com/$NV_REPO/releases/latest")" ||
      nv_inst_die "could not reach github.com/$NV_REPO (network down, or no releases published yet)"
    tag="${url##*/}"
  fi
  nv_inst_validate_version "$tag"
  printf '%s\n' "$tag"
}

# Constrain the NV_CHECKSUM override to an allowlist. The value is later
# word-split into argv and executed, so accepting an arbitrary string would let
# anyone who can set the env var inject commands (e.g. "shasum -a 256; rm -rf ~").
# Only the two known-safe checkers are permitted; anything else is rejected.
nv_inst_validate_checksum() {
  [[ -z "${NV_CHECKSUM:-}" ]] && return 0
  case "$NV_CHECKSUM" in
  sha256sum | "shasum -a 256") return 0 ;;
  *)
    nv_inst_die "NV_CHECKSUM must be exactly 'sha256sum' or 'shasum -a 256' (got: '$NV_CHECKSUM')"
    ;;
  esac
}

# Return 0 (unsafe) for a tar member name that is absolute or escapes the
# extraction root via `..` — `tar -xzf` would otherwise write outside $stage.
# The checksum gate already anchors integrity; this is defense-in-depth for the
# one place untrusted bytes are unpacked.
nv_inst_member_is_unsafe() {
  [[ "$1" == /* ]] || [[ "$1" == *"/../"* ]] || [[ "$1" == "../"* ]] || [[ "$1" == ".." ]]
}

# Echo the SHA-256 verifying command as a string ("sha256sum" or "shasum -a 256"),
# or return 1 if neither tool exists. NV_CHECKSUM overrides for tests (validated
# by nv_inst_validate_checksum before this runs).
nv_inst_checksum_cmd() {
  if [[ -n "${NV_CHECKSUM:-}" ]]; then
    printf '%s\n' "$NV_CHECKSUM"
  elif command -v sha256sum >/dev/null 2>&1; then
    printf 'sha256sum\n'
  elif command -v shasum >/dev/null 2>&1; then
    printf 'shasum -a 256\n'
  else
    return 1
  fi
}

nv_inst_download_url() {
  printf 'https://github.com/%s/releases/download/%s/nv-%s.tar.gz\n' "$NV_REPO" "$1" "$1"
}

nv_inst_checksum_url() {
  printf 'https://github.com/%s/releases/download/%s/SHA256SUMS\n' "$NV_REPO" "$1"
}

# Return 0 if $1 is a directory on $PATH. The optional $2 is a colon-separated
# search list (defaults to $PATH) so tests can pass it explicitly instead of
# mutating the global $PATH.
nv_inst_on_path() {
  local dir="$1" search="${2:-${PATH:-}}" parts=()
  local d
  IFS=: read -ra parts <<<"$search"
  for d in "${parts[@]}"; do
    [[ "$d" == "$dir" ]] && return 0
  done
  return 1
}

# If $1 is not on $PATH, append an export line to the matching shell rc and echo
# its path. No-op (and no output) if $1 is already on $PATH, or if the export is
# already present. For system-wide installs /usr/local/bin is virtually always on
# PATH already, so this rarely fires — it exists for unusual setups.
nv_inst_ensure_path() {
  local dir="$1" rc line shell
  # A bindir with whitespace would break the quoted export line below and any
  # later PATH split; the value is user-controllable (NV_BINDIR), so refuse it
  # rather than emit a malformed rc entry.
  [[ -z "$dir" ]] && return 1
  [[ "$dir" == *[[:space:]]* ]] && {
    nv_inst_warn "not adding '$dir' to PATH: it contains whitespace; add it to your shell rc manually"
    return 1
  }
  nv_inst_on_path "$dir" && return 0
  shell="$(basename "${SHELL:-bash}")"
  case "$shell" in
  zsh) rc="$HOME/.zshrc" ;;
  bash) rc="$HOME/.bashrc" ;;
  *) rc="$HOME/.profile" ;;
  esac
  line="export PATH=\"$dir:\$PATH\""
  if [[ -f "$rc" ]] && grep -qF "$line" "$rc" 2>/dev/null; then
    return 0
  fi
  {
    echo ""
    echo "# added by nv installer"
    echo "$line"
  } >>"$rc"
  printf '%s\n' "$rc"
}

###
### :::: install flow :::: #############
###

nv_inst_run() {
  local version=""
  while (($#)); do
    case "$1" in
    --version)
      shift
      (($#)) || nv_inst_die "--version needs a value"
      version="$1"
      shift
      ;;
    --version=*)
      version="${1#*=}"
      shift
      ;;
    --help | -h)
      nv_inst_info "Usage: curl -fsSL .../install.sh | bash [--version x.y.z]"
      nv_inst_info "Env: NV_INSTALL_DIR (~/.nv), NV_BINDIR (/usr/local/bin)"
      exit 0
      ;;
    *)
      nv_inst_die "unknown option: $1 (try --help)"
      ;;
    esac
  done

  command -v curl >/dev/null 2>&1 || nv_inst_die "curl is required to install nv"
  command -v tar >/dev/null 2>&1 || nv_inst_die "tar is required to install nv"

  # An explicit --version is validated up front; a resolved-latest tag is
  # validated inside nv_inst_resolve_version. Either way we never reach the
  # download with an unvalidated version.
  [[ -n "$version" ]] && nv_inst_validate_version "$version"

  # Constrain the checksum override before it is word-split into argv.
  nv_inst_validate_checksum

  local os
  os="$(nv_inst_os)" ||
    nv_inst_die "unsupported OS: $(uname -s) (nv supports macOS and Linux)"

  if [[ "$os" == "darwin" ]] && ! nv_inst_bash_ok; then
    nv_inst_die "nv needs Bash 5+; this macOS has $(printf '%s.%s' \
      "${BASH_VERSINFO[0]:-?}" "${BASH_VERSINFO[1]:-?}"). Fix: brew install bash, \
 then restart your shell and re-run the installer."
  fi

  [[ -n "$version" ]] || version="$(nv_inst_resolve_version)"
  nv_inst_info "Installing nv $version from $NV_REPO"

  _nv_inst_tmp="$(mktemp -d)"
  local sums_file="$_nv_inst_tmp/SHA256SUMS"
  local tarball="$_nv_inst_tmp/nv-$version.tar.gz"
  # stage/ lives under _nv_inst_tmp so the EXIT trap cleans everything in one place.
  trap 'rm -rf "$_nv_inst_tmp"' EXIT

  # Create the install tree under a restrictive umask so ~/.nv and its contents
  # never inherit a loose umask (e.g. 000) from the caller's environment.
  umask 022

  curl -fsSL -o "$tarball" "$(nv_inst_download_url "$version")" ||
    nv_inst_die "download failed: $(nv_inst_download_url "$version")"
  curl -fsSL -o "$sums_file" "$(nv_inst_checksum_url "$version")" ||
    nv_inst_die "checksum file download failed"

  local ck_str
  ck_str="$(nv_inst_checksum_cmd)" ||
    nv_inst_die "need 'sha256sum' or 'shasum' to verify the download"
  # shellcheck disable=SC2206 # split a trusted internal string into argv
  local -a ck=(${ck_str})
  (cd "$_nv_inst_tmp" && "${ck[@]}" -c SHA256SUMS >/dev/null 2>&1) ||
    nv_inst_die "checksum mismatch — the download was corrupted or tampered with; aborting"

  # Extract into a staging dir, then swap into NV_INSTALL_DIR (back up the old
  # tree first so a failure rolls back instead of leaving a half-installed CLI).
  local stage="$_nv_inst_tmp/stage"
  mkdir -p "$stage"
  # Refuse a tarball whose members are absolute or escape via `..` before
  # extracting — defense-in-depth on top of the checksum gate. A `tar -tzf`
  # failure (corrupt/empty artefact) also aborts rather than silently no-op.
  local _members _m
  _members="$(tar -tzf "$tarball" 2>/dev/null)" ||
    nv_inst_die "could not read tarball contents; refusing to extract"
  while IFS= read -r _m; do
    nv_inst_member_is_unsafe "$_m" &&
      nv_inst_die "tarball contains an unsafe path; refusing to extract"
  done <<<"$_members"
  # --no-same-owner: don't try to reproduce the tarball's ownership (which may
  # not exist locally); extract as the invoking user. Prevents permission errors
  # and any adversary-controlled ownership in a compromised release artefact.
  tar -xzf "$tarball" -C "$stage" --no-same-owner || nv_inst_die "extraction failed"

  # Guard against wiping an unrelated directory. NV_INSTALL_DIR defaults to
  # ~/.nv, but if a user points it at e.g. $HOME we must not `mv` the whole tree
  # away. Only proceed when it does not exist, is empty, or is a recognised nv
  # install (contains bin/nv). Otherwise refuse rather than move/overwrite it.
  local backup=""
  if [[ -e "$NV_INSTALL_DIR" ]]; then
    if [[ -n "$(find "$NV_INSTALL_DIR" -maxdepth 0 -type d -empty 2>/dev/null)" ]]; then
      : # empty directory — safe to back up and replace
    elif [[ -e "$NV_INSTALL_DIR/bin/nv" ]]; then
      : # existing nv install — safe to upgrade in place
    else
      nv_inst_die "$NV_INSTALL_DIR exists, is non-empty, and is not an nv install (no bin/nv); refusing to overwrite it"
    fi
    backup="$NV_INSTALL_DIR.old.$$"
    mv "$NV_INSTALL_DIR" "$backup"
  fi
  mkdir -p "$NV_INSTALL_DIR"
  if ! mv "$stage"/* "$NV_INSTALL_DIR"/ 2>/dev/null; then
    [[ -n "$backup" ]] && {
      rm -rf "$NV_INSTALL_DIR"
      mv "$backup" "$NV_INSTALL_DIR"
    }
    nv_inst_die "failed to place files into $NV_INSTALL_DIR"
  fi
  [[ -n "$backup" ]] && rm -rf "$backup"

  # System-wide symlink /usr/local/bin/nv -> NV_INSTALL_DIR/bin/nv. Use sudo only
  # for this one link (and only if /usr/local/bin isn't user-writable).
  local target="$NV_INSTALL_DIR/bin/nv"
  [[ -x "$target" ]] || nv_inst_die "installed nv binary not executable: $target"
  if [[ -w "$NV_BINDIR" ]]; then
    ln -sfn "$target" "$NV_BINDIR/nv"
  elif command -v sudo >/dev/null 2>&1; then
    nv_inst_warn "$NV_BINDIR is not writable — creating the symlink with sudo"
    sudo ln -sfn "$target" "$NV_BINDIR/nv"
  else
    nv_inst_warn "cannot write $NV_BINDIR and sudo is unavailable; create the link yourself:"
    nv_inst_warn "  sudo ln -sf $target $NV_BINDIR/nv"
    nv_inst_warn "(or add $NV_INSTALL_DIR/bin to your PATH)"
  fi

  # Ensure the executable directory is reachable; touch a shell rc only if it
  # genuinely isn't on PATH yet (almost always a no-op for /usr/local/bin).
  local rc
  rc="$(nv_inst_ensure_path "$NV_BINDIR" 2>/dev/null || true)"
  if [[ -n "$rc" ]]; then
    nv_inst_warn "added $NV_BINDIR to PATH via $rc — open a new shell or run: source $rc"
  fi

  nv_inst_ok "Installed nv $version -> $NV_BINDIR/nv"
  nv_inst_info "  source:  $NV_INSTALL_DIR"
  nv_inst_info "  verify:  nv version"
  nv_inst_info "  next:    set NOVITA_API_KEY (or run: nv auth login)"
}

# Run only when executed directly, so unit tests can source the functions above.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  nv_inst_run "$@"
fi
