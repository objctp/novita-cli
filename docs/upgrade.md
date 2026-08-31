# nv upgrade
Update nv in place from the latest GitHub release.
The public installer is fetched from GitHub and re-run: it re-extracts nv
into ~/.nv and refreshes the /usr/local/bin/nv symlink, so an upgrade
replaces the whole install rather than patching it. --version pins the
installer to a tagged release, running that tag's own installer against that
tag's payload, so a downgrade behaves the same way as an upgrade. The value
is validated before it reaches a URL: a crafted token could otherwise steer
the download via curl's path normalisation.

```
nv upgrade [--version <x.y.z>]
```

## Options

```
  --version <x.y.z>  pin the installer to a tagged release (default: latest)
```

## Notes
  The /usr/local/bin/nv symlink step may prompt for sudo.
  nv also checks for a newer release once a day and prints a one-line notice
  when one is available — naming the right command for your install method:
  `nv upgrade`, `npm update -g @objctp/nv`, or `brew upgrade nv`. Set
  NV_NO_UPDATE_CHECK=1 to disable the check.

## Examples

```
# Upgrade to the latest release
$ nv upgrade

# Upgrade to a pinned version
$ nv upgrade --version 0.1.0
```

**API:** `none — downloads and runs the installer from GitHub (NV_UPGRADE_REPO).`

