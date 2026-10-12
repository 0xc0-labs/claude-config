#!/usr/bin/env bash
# The rule: the workspace's CLAUDE.md, Branches and pull requests.
set -uo pipefail

cmd="$(jq -r '.tool_input.command // ""')"
[ -z "$cmd" ] && exit 0

new_branches="$(printf '%s' "$cmd" | perl -ne '
  # The flags between the subcommand and -c stay within one command: they never
  # cross ;, & or |, or a later "git -C dir" would read as "switch -C dir".
  while (/\bgit\b(?:\s+-C\s+\S+)?\s+(?:checkout\s+(?:[^\s;&|]+\s+)*?-[bB]|switch\s+(?:[^\s;&|]+\s+)*?(?:-[cC]|--create|--force-create))\s+([^\s;&|]+)/g) {
    print "$1\n";
  }')"
[ -z "$new_branches" ] && exit 0

while IFS= read -r branch; do
  [ -z "$branch" ] && continue
  if ! printf '%s' "$branch" | grep -qE '^(feat|fix|docs|refactor|chore|ci)/[a-z0-9][a-z0-9.-]*$'; then
    echo "BLOCKED: branch '$branch' does not follow <type>/<slug>: type in feat|fix|docs|refactor|chore|ci, slug in lowercase letters, digits, '.' and '-'." >&2
    exit 2
  fi
done <<<"$new_branches"

exit 0
