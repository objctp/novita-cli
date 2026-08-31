#!/usr/bin/env bash
#
# Update nv in place from the latest GitHub release.
#
# The public installer is fetched from GitHub and re-run: it re-extracts nv
# into ~/.nv and refreshes the /usr/local/bin/nv symlink, so an upgrade
# replaces the whole install rather than patching it. --version pins the
# installer to a tagged release, running that tag's own installer against that
# tag's payload, so a downgrade behaves the same way as an upgrade. The value
# is validated before it reaches a URL: a crafted token could otherwise steer
# the download via curl's path normalisation.
#
# Usage: nv upgrade [--version <x.y.z>]
#
# Options:
#   --version <x.y.z>  pin the installer to a tagged release (default: latest)
#
# Notes:
#   The /usr/local/bin/nv symlink step may prompt for sudo.
#   nv also checks for a newer release once a day and prints a one-line notice
#   when one is available — naming the right command for your install method:
#   `nv upgrade`, `npm update -g @objctp/nv`, or `brew upgrade nv`. Set
#   NV_NO_UPDATE_CHECK=1 to disable the check.
#
# Examples:
# # Upgrade to the latest release
# $ nv upgrade
# # Upgrade to a pinned version
# $ nv upgrade --version 0.1.0
#
# API: none — downloads and runs the installer from GitHub (NV_UPGRADE_REPO).
#

nv::cmd_upgrade() {
  if [[ "${1:-}" == "help" ]]; then
    cat <<'EOF'
Usage: nv upgrade [--version <x.y.z>]   (update nv in place)
  --version <x.y.z>  pin the installer to a tagged release (default: latest)
  (re-runs install.sh from NV_UPGRADE_REPO; the /usr/local/bin symlink step
   may ask for sudo)
EOF
    return 0
  fi
  nv::args_parse "$@"
  nv::args_has help && {
    cat <<'EOF'
Usage: nv upgrade [--version <x.y.z>]   (update nv in place)
EOF
    return 0
  }

  local ver_arg cur url installer
  ver_arg="$(nv::args_get version)"
  # install.sh's own rule, enforced early because the value is interpolated
  # into the download URL before the installer could reject it.
  [[ -z "$ver_arg" || "$ver_arg" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    nv::usage "usage: invalid --version '$ver_arg' (expected x.y.z or vX.Y.Z, e.g. 0.1.0)"
  ver_arg="${ver_arg#v}"
  cur="$(nv::version)"

  # Pin the installer to the matching tag when a version is requested, so a
  # downgrade runs the old installer against the old payload (not main's).
  if [[ -n "$ver_arg" ]]; then
    url="https://raw.githubusercontent.com/${NV_UPGRADE_REPO}/v${ver_arg}/install.sh"
  else
    url="https://raw.githubusercontent.com/${NV_UPGRADE_REPO}/main/install.sh"
  fi

  nv::info "nv ${cur} -> ${ver_arg:-latest}"
  nv::info "re-running installer (the /usr/local/bin symlink step may ask for sudo)..."

  # Download to a temp file first, then execute: piping curl straight into bash
  # would run a partially-fetched script if the connection drops mid-stream.
  # _mktemp registers the file for cleanup by bin/nv's EXIT trap.
  nv::require_cmd curl
  _mktemp installer
  curl -fsSL "$url" -o "$installer" || nv::die "installer download failed: $url"
  local -a install_args=()
  [[ -n "$ver_arg" ]] && install_args+=(--version "$ver_arg")
  bash "$installer" "${install_args[@]}"
}
