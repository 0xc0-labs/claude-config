#!/usr/bin/env bash
# The rule: the workspace's CLAUDE.md, Commits.
set -uo pipefail

cmd="$(jq -r '.tool_input.command // ""')"
[ -z "$cmd" ] && exit 0

printf '%s' "$cmd" | grep -Eq '\bgit\b[^|;&]*\bcommit\b' || exit 0

# A message from a real file, or an amend without one, is not in the command.
if printf '%s' "$cmd" | grep -Eq '[[:space:]](-F|--file)[=[:space:]]+-([[:space:]]|$)'; then
  # Only the heredoc opened on the git commit line: an earlier one is not the message.
  msg="$(printf '%s' "$cmd" | perl -0777 -ne '
    print $2 if /\bgit\b[^\n;&|]*\bcommit\b[^\n]*?<<-?\s*["\x27]?(\w+)["\x27]?[^\n]*\n(.*?)\n\s*\1\s*(?:\n|$)/s')"
elif printf '%s' "$cmd" | grep -Eq '[[:space:]]-([a-zA-Z]*m|-message)[=[:space:]]'; then
  # Every -m or --message value, any quoting, grouped short flags included (-qam).
  msg="$(printf '%s' "$cmd" | perl -ne '
    while (/(?:\s-[a-zA-Z]*m|\s--message)[= ]\s*("([^"\\]*(\\.[^"\\]*)*)"|'"'"'([^'"'"']*)'"'"'|(\S+))/g) {
      print defined($2) ? $2 : defined($4) ? $4 : $5; print "\n";
    }')"
else
  exit 0
fi
[ -z "$msg" ] && exit 0

subject="$(printf '%s' "$msg" | head -1)"

if printf '%s' "$msg" | grep -qiE 'co-authored-by:|generated with|🤖'; then
  echo "BLOCKED: no tooling trailers in commit messages. Drop the Co-Authored-By / generated-by line." >&2
  exit 2
fi

if ! printf '%s' "$subject" | grep -qE '^(feat|fix|docs|refactor|chore|ci)(\([a-z0-9._/-]+\))?!?: .+'; then
  echo "BLOCKED: '$subject' is not a Conventional Commit. Expected <type>(<scope>): <subject> with type in feat|fix|docs|refactor|chore|ci." >&2
  exit 2
fi

if [ "${#subject}" -gt 72 ]; then
  echo "BLOCKED: subject is ${#subject} characters, limit is 72. Move the detail to the body." >&2
  exit 2
fi

if printf '%s' "$subject" | grep -qE '\.$'; then
  echo "BLOCKED: subject must not end with a period." >&2
  exit 2
fi

if printf '%s' "$subject" | grep -qE ': [A-Z]'; then
  echo "BLOCKED: subject starts with a capital. Use lowercase imperative: 'add x', not 'Add x'." >&2
  exit 2
fi

exit 0
