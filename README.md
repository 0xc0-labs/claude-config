# claude-config

Claude Code marketplace and plugin for the `0xc0-labs` organization.

```
.claude-plugin/marketplace.json   the marketplace
plugins/0xc0/                  the plugin
  skills/                         3 skills
  references/                     what more than one skill links to
  hooks/                          guardrails, commit and branch conventions, board loader
```

## Installing

Which repos enable it, and why each sets `autoUpdate`, is the workspace's
`CLAUDE.md` (Claude Code plugins). In the repo's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "0xc0-labs": {
      "source": { "source": "github", "repo": "0xc0-labs/claude-config" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": { "0xc0@0xc0-labs": true }
}
```

That declares and enables the plugin but does not install it. Once per
machine, from the workspace:

```bash
claude plugin marketplace add 0xc0-labs/claude-config
claude plugin install 0xc0@0xc0-labs --scope project
```

Then start a new session: plugins load at startup.

## Skills

| Skill          | What for                                                  |
|----------------|-----------------------------------------------------------|
| `vault-secret` | where a secret goes in Vault, how it is granted, written and rotated |
| `orchestrate`  | the workspace session: plans a change across repos, writes each repo's issue as its contract (parent and sub-issues, "blocked by", related issues), gates them to Ready, wakes each repo's session, checks the whole set |
| `work-issue`   | a repo's session: back on an up-to-date `main` unless its own PR is open, claims this repo's Ready issue of highest priority, works it up to a draft PR (in an application repo, around gentle-ai's own workflow), reports back in a fixed shape, takes the next |

They live in the plugin, not in a single repo, because they apply in all of
them: secrets show up everywhere, and every repo works the same way (the
workspace's `docs/design/how-we-work.md`). A repo's session, named as the
workspace's `CLAUDE.md` says (Sessions), starts working with
`claude -n <name> "/0xc0:work-issue"`. Skills tied to one repo live in that
repo's `.claude/skills/` instead — see `infrastructure/`.

What both `orchestrate` and `work-issue` do on GitHub, relating two issues
and backing off a rate limit, lives once in
[`plugins/0xc0/references/github.md`](plugins/0xc0/references/github.md),
and each skill links to it.

Claude Code replaces a bare `$1`, `$2`… in a `SKILL.md` with words of the
skill's arguments, so a snippet braces them, `"${1}"`, or uses a named
variable. A session's shell can be zsh, where arrays start at 1, so no snippet
uses one. `hooks/tests/skills.sh` fails on either.

## Hooks

- `board.sh` — `SessionStart`: loads the org project board into every
  session, with the rule that no work starts without an issue. In the
  workspace, the orchestrator's session, the whole board. In a repo's own
  session, that repo's Ready (by priority), In Progress and Blocked issues,
  and only counts for the rest. Every session shares the operator's token and
  so GitHub's limits: the board is read once for all of them, into
  `~/.cache/0xc0/board.json` (or under `$XDG_CACHE_HOME`), reused for 120
  seconds, with a lock so sessions starting together read it once. A failed
  read leaves the last board with a note; a rate limit pauses reads for five
  minutes. `tests/board.sh` checks it against a stand-in `gh`.
- `no-apply.sh` — blocks `tofu/terraform apply|destroy`, and `ansible-playbook`
  or `scripts/ansible` without `--check`.
- `guard-files.sh` — blocks touching the state, and writing a secrets file
  (`.env`, `*secrets.yaml`, `*.sops.*`, private keys) into a repo: secrets live
  in Vault. gitops' `vault-secrets.yaml`, which only names Vault paths, is let
  through. It only sees Edit and Write: a file written from a
  shell command is not checked.
- `commit-msg.sh` — rejects a commit whose message, from `-m` (grouped flags
  such as `-qam` included) or from a heredoc through `-F -`, has a subject that
  is not a Conventional Commit, is over 72 characters, ends in a period,
  starts with a capital, or carries a `Co-Authored-By` / generated-by trailer.
- `branch-name.sh` — rejects creating a branch (`git switch -c`, `git checkout
  -b`, with or without `-C <dir>`) whose name is not `<type>/<slug>`: a commit
  type, then lowercase letters, digits, `.` and `-`.

They require `jq` and `perl` on the PATH. `hooks/tests/run.sh` runs every case
in `hooks/tests/cases.jsonl` through its hook, then `board.sh`'s and the
skills' checks; the `hooks` workflow runs it on every PR that touches the
hooks, the skills or the references.

## Versioning

The plugin's version lives in `plugins/0xc0/.claude-plugin/plugin.json`
alone: the marketplace entry declares none, since Claude Code takes
`plugin.json`'s over it without warning. Every change under `plugins/0xc0/`
bumps it (the workspace's `CLAUDE.md`, Claude Code plugins), and the
`plugin-version` workflow fails a PR that does not.

## Validate

```bash
claude plugin validate .
```
