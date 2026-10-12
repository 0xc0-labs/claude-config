#!/usr/bin/env bash
# WorktreeCreate. Where the worktree goes, and why the autopilot declares it,
# not the plugin: the README, Hooks.
# Claude Code takes the last stdout line as the path: all else goes to stderr.
set -uo pipefail

input="$(cat)"
name="$(jq -r '.name // ""' <<<"$input")"
from="$(jq -r '.cwd // ""' <<<"$input")"
[ -n "$from" ] || from="$PWD"
refuse() { echo "worktree-create: $*" >&2; exit 1; }

[[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || refuse "name '$name' is not [a-z0-9][a-z0-9._-]*"
repo="$(git -C "$from" rev-parse --show-toplevel 2>/dev/null)" || refuse "$from is not in a git repo"
workspace="$(dirname "$repo")"
[ -f "$workspace/CLAUDE.md" ] || refuse "$repo is not directly under a workspace that carries CLAUDE.md"
path="$workspace/.worktrees/$name"

git -C "$repo" fetch --quiet origin >&2 || refuse "git fetch origin failed in $repo"
mkdir -p "$workspace/.worktrees" || refuse "cannot create $workspace/.worktrees"
git -C "$repo" worktree add --quiet --detach "$path" origin/main >&2 || refuse "git worktree add $path origin/main failed"
echo "$path"
