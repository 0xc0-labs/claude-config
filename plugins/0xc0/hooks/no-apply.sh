#!/usr/bin/env bash
# The rule: the workspace's CLAUDE.md, Rules that apply in every repo.
set -uo pipefail

cmd="$(jq -r '.tool_input.command // ""')"
[ -z "$cmd" ] && exit 0

if printf '%s' "$cmd" | grep -Eq '\b(tofu|terraform)\b[^|;&]*\b(apply|destroy)\b'; then
  echo "BLOCKED: the apply/destroy is run by the human after manual approval of the PR. Use 'tofu plan'." >&2
  exit 2
fi

# scripts/ansible is how infrastructure runs ansible-playbook: same rule.
if printf '%s' "$cmd" | grep -Eq '\bansible-playbook\b|scripts/ansible\b' \
   && ! printf '%s' "$cmd" | grep -Eq '(--check|-C)\b'; then
  echo "BLOCKED: ansible-playbook (or scripts/ansible) only with --check. The real run is launched by the human." >&2
  exit 2
fi

exit 0
