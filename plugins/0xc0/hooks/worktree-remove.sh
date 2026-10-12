#!/usr/bin/env bash
# WorktreeRemove: removes a linked worktree, never the primary clone. Claude
# Code leaves a hook-created worktree's branch alone, so this deletes it, but
# only when origin holds its commits: an unpushed branch is their only copy.
set -uo pipefail

path="$(jq -r '.worktree_path // ""')"
refuse() { echo "worktree-remove: $*" >&2; exit 1; }

[ -n "$path" ] || refuse "no worktree_path in the hook's input"
[ -d "$path" ] || { echo "worktree-remove: $path is already gone" >&2; exit 0; }
top="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" || refuse "$path is not in a git repo"
own="$(git -C "$path" rev-parse --path-format=absolute --git-dir)"
common="$(git -C "$path" rev-parse --path-format=absolute --git-common-dir)"
[ "$own" != "$common" ] || refuse "$path is the primary clone, not a linked worktree"
[ "$top" = "$(cd "$path" && pwd -P)" ] || refuse "$path is inside a worktree, not its root"
repo="$(dirname "$common")"
branch="$(git -C "$path" branch --show-current)"

git -C "$repo" worktree remove --force "$path" >&2 || refuse "git worktree remove $path failed"
git -C "$repo" worktree prune >&2

[ -n "$branch" ] || exit 0
pushed="$(git -C "$repo" ls-remote --heads origin "refs/heads/$branch" 2>/dev/null | cut -f1)"
if [ -n "$pushed" ] && git -C "$repo" merge-base --is-ancestor "$branch" "$pushed" 2>/dev/null; then
  git -C "$repo" branch --quiet -D "$branch" >&2
else
  echo "worktree-remove: kept branch $branch, origin does not hold all of it" >&2
fi
exit 0
