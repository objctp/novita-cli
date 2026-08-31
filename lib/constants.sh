#!/usr/bin/env bash
#
# Novita CLI — tunable literals (the "magic values" that are NOT the API wire
# contract). Contract constants (namespace base URLs, REST paths) live closer to
# the code that uses them (lib/common.sh, lib/resource.sh); this file is the
# single home for the defaults, ceilings and magic numbers the rest of the CLI
# would otherwise hardcode inline. Scalars only.
# Usage: sourced by lib/common.sh, so every lib/ and commands/ file has these

# shellcheck disable=SC2034 # every value here is consumed by another module
[[ -n "${_NV_CONSTANTS:-}" ]] && return 0
_NV_CONSTANTS=1

# Self-sufficient NV_ROOT so this file can be sourced standalone (e.g. tests)
# without common.sh having run first; common.sh sets the same value when present.
NV_ROOT="${NV_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)}"

###
### :::: timeouts (seconds) :::: ###############################################
###

# curl --connect-timeout, applied on both namespaces and the per-endpoint
# serverless invoke. A single short budget: we only need the TCP/TLS handshake
# to start.
NV_TIMEOUT_CONNECT=15

# Per-route --max-time ceilings. The serverless job invoke blocks on job
# completion, so it gets a longer budget than the control namespaces.
NV_TIMEOUT_API=120
NV_TIMEOUT_INVOKE=300

###
### :::: limits & ceilings :::: ################################################
###

# API ceiling on --limit (page size) for the v2 cursor-paginated lists.
NV_PAGE_LIMIT_MAX=1000

# Page size used when a list endpoint REQUIRES pagination params and the user
# gave none (the billing transaction list demands pageNo/pageSize).
NV_DEFAULT_PAGE_SIZE=20

###
### :::: release & self-update :::: ############################################
###

# GitHub slug the `nv upgrade` command re-runs install.sh from (and the
# update-check polls for a newer tag). Keep in step with install.sh's NV_REPO.
NV_UPGRADE_REPO="${NV_UPGRADE_REPO:-objctp/novita-cli}"

###
### :::: default sizes & paths :::: ############################################
###

# Default network-storage mount point when --mount is omitted on pod/endpoint
# volume mounts (the Novita docs use /data in their examples).
NV_DEFAULT_MOUNT_POINT=/data

# Default rootfs (system disk) size in GB for pod/endpoint create when
# --rootfs-gb is omitted.
NV_DEFAULT_ROOTFS_GB=20

# Per-user config dir for credentials that MUST survive any install method.
# ${XDG_CONFIG_HOME:-$HOME/.config}/novita follows the XDG base-dir spec.
# `nv auth` writes the API key here; bin/nv loads it on every invocation, so a
# key stored once works whether nv came from install.sh, npm, or a source
# checkout. Override with NV_CONFIG_HOME if you prefer another location.
NV_CONFIG_HOME="${NV_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/novita}"

# Multi-account credential store, under NV_CONFIG_HOME. One file per account
# (each mode 600, the dir 700); `active` is a plain file holding the name of the
# currently-selected account. Login is additive: `nv auth login` adds an account
# and marks it active rather than replacing.
NV_CREDS_DIR="$NV_CONFIG_HOME/credentials.d"
NV_ACTIVE_FILE="$NV_CONFIG_HOME/active"
