#!/usr/bin/env bash
# Fails when a shared skill would not load: Claude Code and Antigravity find a skill by the
# frontmatter of its SKILL.md, and a name that differs from the folder name breaks the
# agents.lock.json "skills" list and the skill index in AGENTS.shared.md.
#
#   bash agents/tests/skills-frontmatter.sh
set -uo pipefail
cd "$(dirname "$0")/../skills" || exit 1

bad=0
err() { echo "error: $1" >&2; bad=1; }
for dir in */; do
  name=${dir%/}
  f="$name/SKILL.md"
  [[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || err "$name: folder name must be kebab-case"
  [[ -f $f ]] || { err "$f missing"; continue; }
  [[ $(head -n 1 "$f" | tr -d '\r') == --- ]] || { err "$f: first line must be ---"; continue; }
  # awk reads to the end: exiting early would SIGPIPE tr and fail the pipeline under pipefail.
  fm=$(tr -d '\r' <"$f" | awk 'NR == 1 { next } !done && /^---$/ { done = 1; next } !done { print } END { exit !done }') \
    || { err "$f: frontmatter has no closing ---"; continue; }
  fm_name=$(sed -n 's/^name:[[:space:]]*//p' <<<"$fm")
  fm_desc=$(sed -n 's/^description:[[:space:]]*//p' <<<"$fm")
  [[ $fm_name == "$name" ]] || err "$f: name is '$fm_name', must equal the folder name '$name'"
  [[ -n $fm_desc ]] || err "$f: description is empty"
  ((${#fm_desc} <= 1024)) || err "$f: description is ${#fm_desc} characters; keep it at most 1024"
  grep -q "\`$name\`" ../AGENTS.shared.md || err "$name: no row in the Skills table of AGENTS.shared.md"
done
((bad == 0)) && echo "skills: $(ls -d */ | tr -d / | tr '\n' ' ')ok"
exit $bad
