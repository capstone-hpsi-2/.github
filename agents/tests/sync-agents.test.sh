#!/usr/bin/env bash
# Runs agents/scripts/sync-agents.sh --local against a throwaway consumer repo built in the old
# layout (feature-branch skill, older sync script), then hand-edits each generated file and asserts
# that --check fails on it. A source change that breaks the sync fails here instead of in every
# repo's daily sync job.
#
#   bash agents/tests/sync-agents.test.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]//\\//}")" && pwd)
src_root=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
g() { git -C "$repo" -c user.name=test -c user.email=test@example.invalid -c core.autocrlf=false "$@"; }

pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n%s\n' "$1" "${2:0:600}"; }

mkdir -p "$repo/scripts" "$repo/.agents/skills/feature-branch" "$repo/.agents/skills/local-bench"
g init -q
printf '%s\n' '# AGENTS.md: demo' '' '<!-- BEGIN SHARED old -->' 'old shared text' '<!-- END SHARED -->' '' \
  '## demo specifics' 'Local rule.' >"$repo/AGENTS.md"
printf '@AGENTS.md\n' >"$repo/CLAUDE.md"
printf 'x\n' >"$repo/.agents/skills/feature-branch/SKILL.md"
printf 'local\n' >"$repo/.agents/skills/local-bench/SKILL.md"
# The new lock template copied over first: the wrong order, which once left feature-branch behind.
printf '%s\n' '{' '  "repo": "capstone-hpsi-2/.github",' '  "sha": "BOOTSTRAP",' '  "path": "agents",' \
  '  "skills": ["agents-md-placement", "create-pr", "pr-review"]' '}' >"$repo/agents.lock.json"
# An older script, so the sync replaces the file it is running from.
{ cat "$src_root/agents/scripts/sync-agents.sh"; printf '# older copy\n'; } >"$repo/scripts/sync-agents.sh"

sync() { (cd "$repo" && bash scripts/sync-agents.sh "$@" --local "$src_root") >"$tmp/out" 2>&1; }

if sync; then ok; else bad "first sync" "$(cat "$tmp/out")"; fi
[[ ! -e $repo/.agents/skills/feature-branch && ! -e $repo/.claude/skills/feature-branch ]] && ok || bad "retired skill removed" "$(ls "$repo/.agents/skills")"
[[ -f $repo/.claude/skills/local-bench/SKILL.md ]] && ok || bad "repo-local skill mirrored" ""
cmp -s "$repo/scripts/sync-agents.sh" "$src_root/agents/scripts/sync-agents.sh" && ok || bad "sync script replaced itself" ""
[[ -f $repo/.github/workflows/agents.yml ]] && ok || bad "workflow copied outside CI" ""
grep -q 'old shared text' "$repo/AGENTS.md" && bad "shared block rewritten" "" || ok
grep -q 'Local rule.' "$repo/AGENTS.md" && ok || bad "specifics kept" ""

g add -A && g update-index --chmod=+x scripts/agents-guard.sh scripts/sync-agents.sh && g commit -qm base
if sync --check; then ok; else bad "check after sync" "$(cat "$tmp/out")"; fi
# A second run must change nothing.
sync && [[ -z $(g status --porcelain) ]] && ok || bad "second sync is a no-op" "$(g status --porcelain)"

reset() { g checkout -q -- . && g clean -fdq && g reset -q --hard; }
tamper() { # name, expected text in the --check output, then a command that changes the repo
  local name=$1 want=$2
  shift 2
  "$@"
  if sync --check; then bad "tamper: $name must fail --check" "$(cat "$tmp/out")"
  elif grep -qF -- "$want" "$tmp/out"; then ok
  else bad "tamper: $name must report '$want'" "$(cat "$tmp/out")"; fi
  reset
}
append() { printf '%s\n' "$2" >>"$repo/$1"; }
tamper "shared block word" "AGENTS.md shared block" sed -i 's/^Each fact lives in one file/Each fact lives in two files/' "$repo/AGENTS.md"
tamper ".claude/skills copy" ".claude/skills/ is not a copy" append .claude/skills/create-pr/SKILL.md x
tamper "settings.json" ".claude/settings.json" append .claude/settings.json ' '
tamper "shared skill" ".agents/skills/pr-review/" append .agents/skills/pr-review/SKILL.md x
tamper "guard script" "scripts/agents-guard.sh" append scripts/agents-guard.sh '# x'
tamper "sync script" "scripts/sync-agents.sh" append scripts/sync-agents.sh '# x'
tamper "GEMINI.md" "GEMINI.md must not exist" append GEMINI.md x
add_rules() { mkdir -p "$repo/.claude/rules" && printf 'x\n' >"$repo/.claude/rules/x.md" && g add .claude/rules/x.md; }
tamper "tracked .claude/rules" ".claude/rules/x.md must not exist" add_rules
revive() { mkdir -p "$repo/.agents/skills/feature-branch" && printf 'x\n' >"$repo/.agents/skills/feature-branch/SKILL.md"; }
tamper "retired skill back" "skill feature-branch is no longer shared" revive
tamper "guard mode 644" "needs 100755" g update-index --chmod=-x scripts/agents-guard.sh
lock_skills() { sed -i 's/, "pr-review"//' "$repo/agents.lock.json"; }
tamper "lock skills list" "agents.lock.json skills" lock_skills

append AGENTS.md 'Another local rule.'
if sync --check; then ok; else bad "specifics edit passes --check" "$(cat "$tmp/out")"; fi
reset

conflict() { printf '%s\n' '<<<<<<< HEAD' '{}' '=======' '{}' '>>>>>>> x' >"$repo/agents.lock.json"; }
conflict
if sync; then bad "conflicted lock must fail" ""; else grep -q 'git checkout --ours agents.lock.json' "$tmp/out" && ok || bad "conflicted lock names the fix" "$(cat "$tmp/out")"; fi
reset

# In CI the workflow file is left alone: GITHUB_TOKEN may not push it.
append .github/workflows/agents.yml '# local'
g commit -qam wf
(cd "$repo" && GITHUB_ACTIONS=true bash scripts/sync-agents.sh --local "$src_root") >"$tmp/out" 2>&1
tail -n 1 "$repo/.github/workflows/agents.yml" | grep -q '# local' && ok || bad "CI sync leaves the workflow" ""
if sync --check && grep -q 'note: .github/workflows/agents.yml differs' "$tmp/out"; then ok; else bad "workflow drift only warns" "$(cat "$tmp/out")"; fi

echo "sync: passed $pass, failed $fail"
((fail == 0))
