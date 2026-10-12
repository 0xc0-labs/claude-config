#!/usr/bin/env bash
# worktree-create.sh and worktree-remove.sh on a throwaway pair, never the
# network: a bare origin, and a workspace carrying CLAUDE.md with a clone of
# it. Run by run.sh.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
n=0; failed=0
fail() { failed=$((failed + 1)); echo "FAIL [worktree/$1] $2"; }
check() {  # check <case> <description> <command...>
  local c="$1" d="$2"; shift 2; n=$((n + 1))
  "$@" >/dev/null 2>&1 || fail "$c" "$d"
}
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

commit() { git -C "$1" commit -q --allow-empty -m "$2"; }
create() {  # create <cwd> <name>: the hook's stdout in $tmp/out, its exit code returned
  jq -n --arg cwd "$1" --arg name "$2" '{hook_event_name: "WorktreeCreate", cwd: $cwd, name: $name}' \
    | bash "$here/../worktree-create.sh" > "$tmp/out" 2>"$tmp/err"
}
remove() {  # remove <worktree path>
  jq -n --arg p "$1" '{hook_event_name: "WorktreeRemove", worktree_path: $p}' \
    | bash "$here/../worktree-remove.sh" >/dev/null 2>"$tmp/err"
}

git init -q --bare -b main "$tmp/origin.git"
mkdir -p "$tmp/ws" && touch "$tmp/ws/CLAUDE.md"
git clone -q "$tmp/origin.git" "$tmp/ws/payload" 2>/dev/null
git -C "$tmp/ws/payload" symbolic-ref HEAD refs/heads/main
commit "$tmp/ws/payload" one && git -C "$tmp/ws/payload" push -q origin main
# origin moves on after the clone: the worktree must start from it, fetched.
git clone -q "$tmp/origin.git" "$tmp/other" && commit "$tmp/other" two && git -C "$tmp/other" push -q origin main
want="$(git -C "$tmp/other" rev-parse HEAD)"

# Created beside the repo, detached at the fetched origin/main, only the path on stdout.
wt="$tmp/ws/.worktrees/payload-99"
create "$tmp/ws/payload" payload-99; code=$?
check create "exits 0 (stderr: $(head -1 "$tmp/err"))" test "$code" -eq 0
check create "prints only the path, got '$(cat "$tmp/out")'" test "$(cat "$tmp/out")" = "$wt"
check create "is a worktree of the repo" sh -c "git -C '$tmp/ws/payload' worktree list --porcelain | grep -qxF 'worktree $wt'"
check create "HEAD detached" test -z "$(git -C "$wt" branch --show-current)"
check create "HEAD at origin/main as fetched" test "$(git -C "$wt" rev-parse HEAD)" = "$want"

# From a subdirectory of the repo: the same workspace.
mkdir -p "$tmp/ws/payload/src"
create "$tmp/ws/payload/src" payload-98; code=$?
check subdir "exits 0 from a subdirectory" test "$code" -eq 0
check subdir "lands in the workspace" test "$(cat "$tmp/out")" = "$tmp/ws/.worktrees/payload-98"

# Refused: a repo not directly under a workspace that carries CLAUDE.md.
git clone -q "$tmp/origin.git" "$tmp/loose/payload"
create "$tmp/loose/payload" payload-97; code=$?
check refuse "exits non-zero outside a workspace" test "$code" -ne 0
check refuse "prints no path outside a workspace" test ! -s "$tmp/out"
check refuse "says why" grep -q 'workspace' "$tmp/err"
check refuse "creates nothing outside a workspace" test ! -e "$tmp/loose/.worktrees"

# Refused: a name that is not [a-z0-9][a-z0-9._-]*.
for bad in ../escape Payload-1 .hidden "a/b" ""; do
  create "$tmp/ws/payload" "$bad"; code=$?
  check name "refuses the name '$bad'" test "$code" -ne 0
done
check name "creates nothing for a refused name" test ! -e "$tmp/ws/escape"

# Removed with an unpushed branch: the worktree goes, the branch stays.
git -C "$wt" switch -q -c feat/unpushed && commit "$wt" three
remove "$wt"; code=$?
check keep "exits 0 (stderr: $(head -1 "$tmp/err"))" test "$code" -eq 0
check keep "the worktree is gone" test ! -e "$wt"
check keep "git no longer lists it" sh -c "! git -C '$tmp/ws/payload' worktree list --porcelain | grep -qxF 'worktree $wt'"
check keep "the unpushed branch stays" git -C "$tmp/ws/payload" rev-parse --verify -q refs/heads/feat/unpushed

# Removed with a pushed branch: both go.
wt2="$tmp/ws/.worktrees/payload-98"
git -C "$wt2" switch -q -c feat/pushed && commit "$wt2" four && git -C "$wt2" push -q origin feat/pushed
remove "$wt2"; code=$?
check pushed "exits 0" test "$code" -eq 0
check pushed "the worktree is gone" test ! -e "$wt2"
check pushed "the pushed branch is deleted" sh -c "! git -C '$tmp/ws/payload' rev-parse --verify -q refs/heads/feat/pushed"

# Refused: the primary clone.
remove "$tmp/ws/payload"; code=$?
check primary "exits non-zero on the primary clone" test "$code" -ne 0
check primary "the primary clone stays" test -d "$tmp/ws/payload/.git"

echo "$((n - failed))/$n worktree cases pass"
[ "$failed" -eq 0 ]
