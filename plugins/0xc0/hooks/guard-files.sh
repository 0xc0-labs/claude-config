#!/usr/bin/env bash
# The rule: the workspace's CLAUDE.md, Rules that apply in every repo.
set -uo pipefail

path="$(jq -r '.tool_input.file_path // ""')"
[ -z "$path" ] && exit 0

case "$path" in
  *.tfstate|*.tfstate.backup)
    echo "BLOCKED: the state is not edited by hand." >&2
    exit 2
    ;;
  *.auto.tfvars|*vault-pass*|*age.key*|*/id_ed25519|*/id_rsa)
    echo "BLOCKED: sensitive material. Secrets live in Vault, never in a repo." >&2
    exit 2
    ;;
esac

# vault-secrets.yaml only names Vault paths; it holds no value.
case "$path" in
  */vault-secrets.yaml) ;;
  *secrets.yaml|*secrets.yml|*.env|*.sops.*|*.enc.*)
    echo "BLOCKED: '$path' would hold secrets in a repo. They live in Vault: see the vault-secret skill." >&2
    exit 2
    ;;
esac

exit 0
