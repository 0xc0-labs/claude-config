---
name: orchestrate
description: The workspace session's side of how the org works. Plans a change across repos, writes a parent issue in the workspace and one sub-issue per repo as self-contained contracts ordered by "blocked by", gates each to Ready once its blockers are closed and applied, wakes the repo's session, follows the reports, and checks the whole set before calling it done. Use for any change that touches more than one repo, or to hand a repo work from the workspace.
---

# Orchestrating a change

The workspace's `docs/design.md`, How we work, decides; this is how the
orchestrator applies it. The orchestrator plans, writes the contracts, gates
and wakes, and owns integration. It edits the workspace repo and the board,
**no other repo's files**: each repo's session does that, in its own tab.

## 1. Plan

Plan mode first. For every repo: what changes and why, what it needs from
another repo, and the order. The dependency order is `CLAUDE.md`'s:
`.github` → `infrastructure` → `gitops` → `vault` → the applications; a
downstream change waits until the upstream one is applied. Layout and names
are proposed and get the operator's yes before any issue is written.

## 2. Write the contracts

A parent issue in the workspace holds the outcome; each repo gets a
sub-issue. A repo session starts with no memory of this conversation and
cannot read the workspace's design without asking, so **its issue carries
everything, quoted, not linked**:

```markdown
## Outcome
<what is true when this is done>

## Acceptance criteria
- [ ] <checkable>

## Branch
`<type>/<slug>`, the same in every repo of this change.

## Context
<the decisions, names, paths and facts the work needs, quoted>

## Siblings and merge order
1. 0xc0-labs/<repo>#<n>: <what>
2. this issue

## Out of scope
<what not to touch, and where it belongs instead>

## Operator steps
<Vault writes, applies, approvals the change needs, or none>
```

The title says what must be true, or the problem, in a plain sentence:
"Runners register without the App key on disk". No type prefix and no repo:
the issue type (Feature, Bug or Task) and the board's Repository field carry
them. The Conventional Commit belongs to the PR, written by the repo's session
for the change it makes; the branch, the same in every repo of the change, is
in each contract.

```sh
gh issue create -R 0xc0-labs/workspace --title "<outcome>" --type <Feature|Bug|Task> --body-file <file>
gh issue create -R 0xc0-labs/<repo> --title "<this repo's part, as an outcome>" --type <Feature|Bug|Task> \
  --parent https://github.com/0xc0-labs/workspace/issues/<parent> --body-file <file>
# Order: the downstream sub-issue is blocked by the upstream one.
gh issue edit <n> -R 0xc0-labs/<downstream> --add-blocked-by https://github.com/0xc0-labs/<upstream>/issues/<m>
```

Every issue goes on the board as Todo, with a `Priority`. IDs by name:

```sh
f=$(gh project field-list 1 --owner 0xc0-labs --format json)
project=$(gh project view 1 --owner 0xc0-labs --format json --jq .id)
field() { jq -r --arg n "$1" '.fields[] | select(.name==$n) | .id' <<<"$f"; }
opt() { jq -r --arg n "$1" --arg o "$2" '.fields[] | select(.name==$n) | .options[] | select(.name==$o) | .id' <<<"$f"; }
item=$(gh project item-add 1 --owner 0xc0-labs --url <issue-url> --format json --jq .id)
gh project item-edit --project-id "$project" --id "$item" --field-id "$(field Status)" --single-select-option-id "$(opt Status Todo)"
gh project item-edit --project-id "$project" --id "$item" --field-id "$(field Priority)" --single-select-option-id "$(opt Priority P2)"
```

Relate, besides parent and "blocked by", what belongs together outside this
change: the design issue behind it, an earlier change it builds on or fixes,
another issue touching the same thing. `gh` has no flag for it yet:

```sh
relate() {  # relate <owner/repo#n> <owner/repo#n>
  a=$(gh issue view "${1#*#}" -R "${1%#*}" --json id -q .id)
  b=$(gh issue view "${2#*#}" -R "${2%#*}" --json id -q .id)
  gh api graphql -f query='mutation($a:ID!,$b:ID!){ addRelatesTo(input:{issueId:$a, relatedIssueId:$b}) { clientMutationId } }' -f a="$a" -f b="$b" >/dev/null
}
```

## 3. Gate to Ready

A sub-issue turns Ready only when both hold:

- its contract is complete (every section above, nothing to guess);
- every issue blocking it is closed **and applied**: for `.github`,
  `infrastructure` and `vault`, the apply on `main` after the merge succeeded;
  for `gitops`, ArgoCD synced it.

```sh
gh issue view <n> -R 0xc0-labs/<repo> --json blockedBy --jq '.blockedBy[] | "\(.number) \(.state)"'
gh run list -R 0xc0-labs/<upstream> -b main -L 3 --json workflowName,conclusion,createdAt
```

Then Status → Ready (`opt Status Ready`).

## 4. Wake the repo's session

`ListAgents`: a session named `<repo>` is open → `SendMessage` to it:
"`<repo>#<n>` is Ready." Nothing more: the issue is the contract, and a
message that adds to it means the issue is incomplete. Not open → ask the
operator to open it; never start a session yourself:

```sh
cd ~/git/github/0xc0-homelab/workspace/<repo> && claude -n <repo> "/0xc0:work-issue"
```

## 5. Follow the reports

A repo session reports: PR, checks, not done, questions. A question for the
operator goes to the operator, verbatim. A question about the contract is
answered **in the issue**, as a comment, then the session is told to look
again. When a PR is merged and applied, gate the next sub-issue (step 3) and
wake its session.

## 6. Integration, before calling it done

Green PRs in every repo are not a working change. Check, and say what was
checked:

- every PR of the set: checks green, `Closes`/`Refs` right, the merge order
  in its body;
- what one repo does to another: the callers of a reusable workflow that
  changed, the plan of a root that reads a policy that changed (it reads with
  the plan role, which must still reach it), a setting a repo inherits from
  the workspace, a plugin or hook a repo's session needs;
- the operator's steps, in order, in one list.

The parent issue closes when its last sub-issue does: through the workspace's
PR of the change when there is one, otherwise by hand, with a comment that
lists the sub-issues and their PRs.

## Never

Edit another repo's files, merge, mark a PR ready, apply, write or rotate a
secret, answer for the operator, or start a repo's session on your own.
