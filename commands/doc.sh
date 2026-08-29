#!/usr/bin/env bash
#
# Read the manual embedded in nv's own source comments.
#
# `nv doc` is the reference surface: every user-facing command and verb carries
# a documentation block in its source file, and this command renders it. Where
# `--help` is a terse reminder of the flags, `nv doc` is the page you read to
# learn a command — arguments, defaults, constraints, caveats, examples, and the
# API call each verb makes. Library internals are never documented here.
#
# Usage: nv doc [command] [verb] [sub-verb]
#

_doc_help() {
  cat <<'EOF'
Usage: nv doc [command] [verb] [sub-verb]

Show the reference documentation for user-facing commands, read from the source
comments. `--help` lists the flags; `nv doc` explains them.

  nv doc                        every command with a one-line summary
  nv doc serverless             a command's overview and its verbs
  nv doc serverless create      one verb: arguments, options, notes, examples

The command name may be abbreviated to any unique prefix (`nv doc serv`).

Verbs are documented by a `# doc: <verb>` block in the command file, collected
in one section above `nv::cmd_<command>`; the comment above a matching
`_<command>_<verb>` function is read as a fallback. Edit those comments to grow
what `nv doc` shows — there is no separate doc file to maintain.
EOF
}

# Resolve a command name to its file: exact match first, else the first command
# whose name starts with the arg (prefix). Prints the path, or nothing.
_doc_resolve() {
  local arg="$1" f
  [[ -f "$NV_ROOT/commands/$arg.sh" ]] && {
    printf '%s' "$NV_ROOT/commands/$arg.sh"
    return 0
  }
  for f in "$NV_ROOT"/commands/*.sh; do
    [[ "$(basename "$f" .sh)" == "$arg"* ]] && {
      printf '%s' "$f"
      return 0
    }
  done
  return 0
}

# A verb's documentation body: its `# doc:` block, else the comment above the
# matching handler function. $3 is the verb as the user types it, so a sub-verb
# arrives space-separated and maps to the underscored handler name.
_doc_body() {
  local file="$1" name="$2" verb="$3" body
  body="$(nv::doc_verb_marker "$file" "$verb")"
  [[ -n "$body" ]] || body="$(nv::doc_func_doc "$file" "_${name}_${verb// /_}")"
  printf '%s' "$body"
}

# First line of a verb's block — the mandatory one-line summary, used by the
# verb index the way the intro's first line is used by the catalogue.
_doc_summary() {
  _doc_body "$1" "$2" "$3" | awk 'NF {print; exit}'
}

# Print "  <verb>  <summary>" rows, descriptions aligned to the longest verb.
# Reads verb names from stdin; $1 file, $2 command name, $3 optional prefix that
# makes each name a sub-verb.
_doc_index() {
  local file="$1" name="$2" prefix="${3:-}" v width=0
  local -a verbs=()
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    verbs+=("$v")
    ((${#v} > width)) && width=${#v}
  done
  ((${#verbs[@]})) || return 0
  for v in "${verbs[@]}"; do
    printf '  %-*s  %s\n' "$width" "$v" "$(_doc_summary "$file" "$name" "${prefix:+$prefix }$v")"
  done
}

# Catalogue: one line per command (name + intro summary).
_doc_catalogue() {
  local f name summary
  for f in "$NV_ROOT"/commands/*.sh; do
    name="$(basename "$f" .sh)"
    summary="$(nv::doc_intro_summary "$f")"
    printf '%-16s %s\n' "nv $name" "$summary"
  done
}

# Command-level: intro, then the verb index. Commands with no verbs (nv api)
# carry their flags in the intro, so the header is suppressed rather than
# printed above nothing.
_doc_command() {
  local file="$1" name="$2" index
  printf 'nv %s\n\n' "$name"
  nv::doc_intro "$file"
  index="$(nv::doc_verbs "$file" | _doc_index "$file" "$name")"
  [[ -n "$index" ]] || return 0
  printf '\nVerbs:\n%s\n' "$index"
}

# Group verb: its own block, then its sub-verb index.
_doc_group() {
  local file="$1" name="$2" group="$3" body index
  printf 'nv %s %s\n\n' "$name" "$group"
  body="$(_doc_body "$file" "$name" "$group")"
  [[ -z "$body" ]] || printf '%s\n' "$body"
  index="$(nv::doc_subverbs "$file" "$group" | _doc_index "$file" "$name" "$group")"
  [[ -n "$index" ]] || return 0
  printf '\nVerbs:\n%s\n' "$index"
}

# Verb-level: the `# doc: <verb>` block, or the handler's comment as a fallback.
_doc_verb() {
  local file="$1" name="$2" verb="$3" body
  printf 'nv %s %s\n\n' "$name" "$verb"
  body="$(_doc_body "$file" "$name" "$verb")"
  if [[ -n "$body" ]]; then
    printf '%s\n' "$body"
  else
    printf '%s\n' "no documented options for 'nv $name $verb' yet"
  fi
}

# True when $3 names a verb of command $2 (in $1).
_doc_is_verb() {
  local v
  while IFS= read -r v; do
    [[ "$v" == "$3" ]] && return 0
  done < <(nv::doc_verbs "$1")
  return 1
}

# True when $4 names a sub-verb of group $3.
_doc_is_subverb() {
  local v
  while IFS= read -r v; do
    [[ "$v" == "$4" ]] && return 0
  done < <(nv::doc_subverbs "$1" "$3")
  return 1
}

nv::cmd_doc() {
  local a="${1:-}" b="${2:-}" c="${3:-}"
  [[ "$a" == "-h" || "$a" == "--help" || "$a" == "help" ]] && {
    _doc_help
    return 0
  }
  if [[ -z "$a" ]]; then
    _doc_catalogue
    return 0
  fi
  local cmdfile
  cmdfile="$(_doc_resolve "$a")"
  if [[ -z "$cmdfile" ]]; then
    printf '%s\n' "no documentation matches '$a'"
    return 0
  fi
  local name
  name="$(basename "$cmdfile" .sh)"
  if [[ -z "$b" ]]; then
    _doc_command "$cmdfile" "$name"
    return 0
  fi
  if ! _doc_is_verb "$cmdfile" "$name" "$b"; then
    printf '%s\n' "no verb '$b' for command '$name'"
    return 0
  fi
  # A group verb owns sub-verbs; without one, show its index rather than a
  # block that would only repeat what the index already says.
  if [[ -n "$(nv::doc_subverbs "$cmdfile" "$b")" ]]; then
    if [[ -z "$c" ]]; then
      _doc_group "$cmdfile" "$name" "$b"
    elif _doc_is_subverb "$cmdfile" "$name" "$b" "$c"; then
      _doc_verb "$cmdfile" "$name" "$b $c"
    else
      printf '%s\n' "no sub-verb '$c' for '$name $b'"
    fi
    return 0
  fi
  _doc_verb "$cmdfile" "$name" "$b"
}
