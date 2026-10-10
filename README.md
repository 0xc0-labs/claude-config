# claude-config

Claude Code marketplace and plugin for the `0xc0-labs` organization.

```
.claude-plugin/marketplace.json   the marketplace
plugins/0xc0/                  the plugin
  agents/                         5 agents
  skills/                         3 skills
  hooks/                          guardrails, commit and branch conventions, board loader
```

## Consuming it from another repo

In the repo's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "0xc0-labs": {
      "source": { "source": "github", "repo": "0xc0-labs/claude-config" }
    }
  },
  "enabledPlugins": { "0xc0@0xc0-labs": true }
}
```

That declares and enables the plugin; each machine still installs it once, as
described in **Installing** under Hooks.

## Agents

| Agent                  | Type      | What for                                   |
|------------------------|-----------|--------------------------------------------|
| `network-reviewer`     | read-only | validates network and firewall vs the transit matrix |
| `iac-reviewer`         | read-only | OpenTofu, Packer, Ansible                  |
| `drift-hunter`         | read-only | drift between real state and code          |
| `infra-builder`        | builder   | implements in `infrastructure/`            |
| `gitops-builder`       | builder   | implements in `gitops/`                    |

The read-only ones cannot edit (`disallowedTools: Edit, Write`). The builders
get closed specifications and stop if anything is ambiguous.

## Skills

| Skill          | What for                                                  |
|----------------|-----------------------------------------------------------|
| `vault-secret` | where a secret goes in Vault, how it is granted, written and rotated |
| `orchestrate`  | the workspace session: plans a change across repos, writes each repo's issue as its contract (parent and sub-issues, "blocked by", related issues), gates them to Ready, wakes each repo's session, checks the whole set |
| `work-issue`   | a repo's session: claims this repo's Ready issue of highest priority, works it up to a draft PR, reports back in a fixed shape, takes the next |

They live in the plugin, not in a single repo, because they apply in all of
them: secrets show up everywhere, and every repo works the same way (the
workspace's `docs/design.md`, How we work). A session is named after its repo
as Herdr names an agent, dots to dashes and a leading dot dropped (`github`,
`offby1-cc`), and starts working with `claude -n <name> "/0xc0:work-issue"`;
the workspace's is `orchestrator`. Skills tied to one repo live in that repo's
`.claude/skills/` instead — see `infrastructure/`.

Claude Code replaces a bare `$1`, `$2`… in a `SKILL.md` with words of the
skill's arguments, so a snippet braces them, `"${1}"`, or uses a named
variable. A session's shell can be zsh, where arrays start at 1, so no snippet
uses one. `hooks/tests/skills.sh` fails on either.

## Hooks

- `board.sh` — `SessionStart`: loads the org project board into every
  session, with the rule that no work starts without an issue. In the
  workspace, the orchestrator's session, the whole board. In a repo's own
  session, that repo's Ready (by priority), In Progress and Blocked issues,
  and only counts for the rest. `tests/board.sh` checks it from a fixture.
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
hooks or the skills.

**Installing.** Declaring the plugin in a project's `.claude/settings.json`
enables it but does not install it. Once per machine, from the workspace:

```bash
claude plugin marketplace add 0xc0-labs/claude-config
claude plugin install 0xc0@0xc0-labs --scope project
```

Then start a new session: plugins load at startup.

## Validate

```bash
claude plugin validate .
```
