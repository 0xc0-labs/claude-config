# GitHub, from a session

What the `orchestrate` and `work-issue` skills both do on GitHub. Each skill
says when; this says how.

## Relate two issues

GitHub's "relates to", besides parent and "blocked by". `gh` has no flag for
it yet:

```sh
relate() {  # relate <owner/repo#n> <owner/repo#n>
  a=$(gh issue view "${1#*#}" -R "${1%#*}" --json id -q .id)
  b=$(gh issue view "${2#*#}" -R "${2%#*}" --json id -q .id)
  gh api graphql -f query='mutation($a:ID!,$b:ID!){ addRelatesTo(input:{issueId:$a, relatedIssueId:$b}) { clientMutationId } }' -f a="$a" -f b="$b" >/dev/null
}
```

## When GitHub rate-limits

The sessions share the operator's token, and the limit that bites is the
secondary one on bursts, where every request during the penalty extends it.
On "rate limit" or "submitted too quickly" from any `gh` call: stop calling
GitHub, say so, and wait in the background, until the reset when the hourly
quota is spent, a few minutes otherwise. Then try once more. Never an
immediate retry, never a loop. The quota, without spending it:

```sh
gh api rate_limit --jq '.resources.graphql | "\(.remaining) left, reset \(.reset | todate)"'
```
