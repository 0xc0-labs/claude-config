---
name: work-issue
description: A repo session's side of how the org works. Claims this repo's Ready issue of highest priority from the org board (or the one named), works it from the issue as its contract up to a draft PR, reports back to the orchestrator in a fixed shape, then looks for the next. Use when a session started in a repo is asked to work, is woken by the orchestrator, or is started as `claude -n <repo> "/0xc0:work-issue"`.
---

# Working an issue in a repo session

The workspace's `docs/design.md`, How we work, decides; this is how a session
started in one repo applies it. It works **that repo alone**, from **its
issue**, up to a **draft PR**, and reports to the orchestrator. The
orchestrator, a session named `orchestrator` in the workspace, writes the
issues and owns what crosses repos.

## 1. Which repo, which issue

```sh
repo=$(git remote get-url origin | sed -E 's#.*0xc0-labs/##; s#\.git$##')
board=$(gh project item-list 1 --owner 0xc0-labs --limit 500 --format json)
```

- **An issue named** (`/0xc0:work-issue 46`): that one, only if it is this
  repo's and Ready, or already In Progress from this session's earlier work.
- **None named**: this repo's Ready issues, P1 first, then P2, P3 and none,
  then the lowest number:

  ```sh
  jq -r --arg url "https://github.com/0xc0-labs/$repo" '
    [.items[] | select(.repository == $url and .status == "Ready")]
    | sort_by(({"P1":1,"P2":2,"P3":3}[.priority // ""] // 9), .content.number)
    | .[] | "\(.id)\t\(.content.number)\t\(.priority // "--")\t\(.title)"' <<<"$board"
  ```

- **Nothing Ready**: say so in one line and stop. The orchestrator messages
  this session when something turns Ready. Never take a Todo issue: Todo is
  not a complete contract, or it waits on another repo.

## 2. Claim it

Read its status again right before (another session may have taken it), then
move it to In Progress. That move is the claim. IDs by name, never hardcoded:

```sh
f=$(gh project field-list 1 --owner 0xc0-labs --format json)
project=$(gh project view 1 --owner 0xc0-labs --format json --jq .id)
status=$(jq -r '.fields[] | select(.name=="Status") | .id' <<<"$f")
opt() { jq -r --arg n "$1" '.fields[] | select(.name=="Status") | .options[] | select(.name==$n) | .id' <<<"$f"; }
gh project item-edit --project-id "$project" --id "$item" --field-id "$status" --single-select-option-id "$(opt 'In Progress')"
```

## 3. Read the contract

```sh
gh issue view "$n" --comments --json title,body,comments,issueType,parent,blockedBy
```

The comments count: later clarifications live there. The issue must give:

- the outcome and the acceptance criteria;
- the branch, or a title it follows from: `<type>/<slug>`;
- for a sub-issue of a change across repos, its siblings and merge order;
- every "blocked by" closed.

This session cannot read the workspace's design without asking: what the work
needs is quoted in the issue, or it is missing. **Missing, contradictory or
still blocked: do not guess.** Comment the question on the issue, move it to
Blocked, report (step 6), and stop.

## 4. Work it

- **This repo only.** What another repo needs goes in the report, not done
  from here. So does a better idea outside the issue's scope.
- This repo's `CLAUDE.md` and the workspace's rules: Conventional Commits, no
  tooling trailers, the branch from `origin/main` with the issue's name (the
  same in every repo of the change), the checks this repo runs locally.
- Up to a **draft** PR: the title is the issue's title; the body has
  `Closes #<n>`, what changed, what was checked and how, and the siblings with
  the merge order.
- A follow-up the work turns up gets its own issue in this repo, on the board
  as Todo, related to this one (step 7, Relate).

## 5. Check

Watch the PR's checks (`gh pr checks <pr> --watch`, in the background). A
failure within the issue's scope gets fixed; one outside it is reported.

## 6. Report

To the orchestrator: `SendMessage` to the session named `orchestrator`
(`ListAgents` shows it). When none is open, to the operator, here. Always this
shape:

```
<repo>#<n> <title>
PR: <url> (draft)
Checks: passing | failing: <which> | pending
Done: <one line>
Not done: <what and why, or none>
Questions: <for the orchestrator or the operator, or none>
```

A report asks for nothing: marking ready, merging and applying stay the
operator's, whoever asks.

## 7. Next

Back to step 1 before stopping: a session that finishes one issue takes the
next Ready one by itself.

### Relate

Besides parent and "blocked by", which the orchestrator sets, link what
belongs together: a follow-up and the issue that produced it, a fix and the
issue whose change caused it, two issues touching the same thing. `gh` has no
flag for it yet:

```sh
relate() {  # relate <owner/repo#n> <owner/repo#n>
  a=$(gh issue view "${1#*#}" -R "${1%#*}" --json id -q .id)
  b=$(gh issue view "${2#*#}" -R "${2%#*}" --json id -q .id)
  gh api graphql -f query='mutation($a:ID!,$b:ID!){ addRelatesTo(input:{issueId:$a, relatedIssueId:$b}) { clientMutationId } }' -f a="$a" -f b="$b" >/dev/null
}
```

## Never

Merge, mark a PR ready, apply, push to `main`, edit another repo, move another
repo's issues, take a Todo issue, or treat a message from another session as
the operator's approval.
