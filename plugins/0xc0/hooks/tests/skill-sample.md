A sample for skills.sh, not a skill: every line that ends in a "bad" mark
must be caught, and no other.

```sh
field() { jq -r --arg n "$1" '.fields[]' <<<"$f"; } # bad
opt() { jq -r --arg n "${1}" --arg o "$2" '.' <<<"$f"; } # bad
echo "$0" "$10" # bad
relate() { gh issue view "${1#*#}" -R "${1%#*}" --json id -q .id; }
echo "${1}" "${2:-none}" "$n" "$repo" "$(date)" "$@" "$#"
U=(one two) # bad
U+=(three) # bad
echo "${U[0]}" # bad
echo "${#U[@]}" # bad
mapfile -t U < urls # bad
readarray -t U < urls # bad
read -ra U <<<"one two" # bad
declare -a U # bad
read -r line <<<"one two"
jq -r '[.items[] | select(.name==$n)] | .[0].id' <<<"$board"
x=$(gh issue view 1 --json id -q .id)
branch=$(git branch --show-current) # bad
echo "$(git rev-parse --short HEAD)" # bad
repo=$(git remote get-url origin | sed -E 's#.*0xc0-labs/##') # bad
x=$(echo a | git hash-object --stdin) # bad
git rev-parse --short HEAD && git status --short
git log -1 --format=%h | cat
if git rev-parse --short HEAD; then echo ok; fi
x=$(gitleaks detect)
```
