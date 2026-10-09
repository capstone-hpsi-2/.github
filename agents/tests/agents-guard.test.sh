#!/usr/bin/env bash
# Feeds Claude Code and Antigravity PreToolUse payloads to agents/scripts/agents-guard.sh inside a
# throwaway consumer repo and asserts allow or deny. Runs every case once per JSON reader found
# (python, node), because the guard picks whichever the machine has.
#
#   bash agents/tests/agents-guard.test.sh
#
# Payload shapes follow https://code.claude.com/docs/en/hooks (PreToolUse input) and
# https://antigravity.google/docs/hooks (PreToolUse input, tool arguments), and match payloads
# captured from Claude Code 2.1 and Antigravity CLI 1.3 on Windows: C:\ paths with backslashes,
# 1-based StartLine/EndLine, workspacePaths as C:/ paths.
#
# The Windows path cases need the repo to have a drive form: on Git Bash cygpath gives it, on Linux
# CI the repo is created under /c/... (AGENTS_GUARD_TEST_DIR) so C:\... maps onto it. Elsewhere
# they are skipped and reported.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]//\\//}")" && pwd)
guard_src="$here/../scripts/agents-guard.sh"

base=${AGENTS_GUARD_TEST_DIR:-}
if [[ -n $base ]]; then
  mkdir -p "$base"
  tmp=$(mktemp -d "$base/guard.XXXXXX")
else
  tmp=$(mktemp -d)
fi
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/scripts" "$repo/.agents/skills/create-pr" "$repo/.agents/skills/local-bench" "$repo/app"
cp "$guard_src" "$repo/scripts/agents-guard.sh"
printf '%s\n' '{' '  "repo": "capstone-hpsi-2/.github",' '  "sha": "BOOTSTRAP",' '  "path": "agents",' \
  '  "skills": ["agents-md-placement", "create-pr", "pr-review"]' '}' >"$repo/agents.lock.json"
# CRLF on purpose: Windows checkouts with core.autocrlf=true have it, payloads never do.
printf '%s\r\n' '# AGENTS.md: demo' '' \
  '<!-- BEGIN SHARED (synced from capstone-hpsi-2/.github agents/AGENTS.shared.md; do not edit here) -->' \
  '## Shared rules' 'Rule one says alpha.' 'Same words here.' '<!-- END SHARED -->' '' \
  '## demo specifics' 'Local rule says beta.' 'Same words here.' >"$repo/AGENTS.md"
block_lines=$(sed -n '3,7p' "$repo/AGENTS.md" | tr -d '\r')
printf 'x\n' >"$repo/.agents/skills/create-pr/SKILL.md"
printf 'x\n' >"$repo/.agents/skills/local-bench/SKILL.md"

winroot= winroot_fwd=
if command -v cygpath >/dev/null 2>&1; then
  winroot=$(cygpath -w "$repo") winroot_fwd=$(cygpath -m "$repo")
elif [[ $repo =~ ^/([a-z])(/.*)$ ]]; then
  d=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
  winroot_fwd="$d:${BASH_REMATCH[2]}" winroot=${winroot_fwd//\//\\}
fi

js() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"} s=${s//$'\n'/\\n} s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

c_common() { printf '"session_id":"t","transcript_path":"/tmp/t.jsonl","cwd":%s,"permission_mode":"acceptEdits","hook_event_name":"PreToolUse","tool_use_id":"toolu_test"' "$(js "${CWD:-$repo}")"; }
c_edit() { printf '{%s,"tool_name":"Edit","tool_input":{"file_path":%s,"old_string":%s,"new_string":%s,"replace_all":false}}' "$(c_common)" "$(js "$1")" "$(js "$2")" "$(js "$3")"; }
c_write() { printf '{%s,"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' "$(c_common)" "$(js "$1")" "$(js "$2")"; }
c_multi() { printf '{%s,"tool_name":"MultiEdit","tool_input":{"file_path":%s,"edits":[{"old_string":%s,"new_string":%s},{"old_string":%s,"new_string":%s}]}}' "$(c_common)" "$(js "$1")" "$(js "$2")" "$(js "$3")" "$(js "$4")" "$(js "$5")"; }

a_common() { printf '"stepIdx":4,"conversationId":"00000000-0000-0000-0000-000000000000","workspacePaths":[%s],"transcriptPath":"t.jsonl","artifactDirectoryPath":"a","modelName":"test"' "$(js "${WS:-$repo}")"; }
a_write() { printf '{"toolCall":{"name":"write_to_file","args":{"TargetFile":%s,"Overwrite":true,"CodeContent":%s,"Description":"t"}},%s}' "$(js "$1")" "$(js "$2")" "$(a_common)"; }
a_replace() { printf '{"toolCall":{"name":"replace_file_content","args":{"TargetFile":%s,"Instruction":"t","Description":"t","AllowMultiple":false,"TargetContent":%s,"ReplacementContent":%s,"StartLine":%s,"EndLine":%s}},%s}' "$(js "$1")" "$(js "$2")" "$(js "$3")" "$4" "$5" "$(a_common)"; }
a_multi() { printf '{"toolCall":{"name":"multi_replace_file_content","args":{"TargetFile":%s,"Instruction":"t","Description":"t","ReplacementChunks":[{"AllowMultiple":false,"TargetContent":%s,"ReplacementContent":%s,"StartLine":%s,"EndLine":%s},{"AllowMultiple":false,"TargetContent":%s,"ReplacementContent":%s,"StartLine":%s,"EndLine":%s}]}},%s}' "$(js "$1")" "$(js "$2")" "$(js "$3")" "$4" "$5" "$(js "$6")" "$(js "$7")" "$8" "$9" "$(a_common)"; }

valid_json() {
  if [[ $reader == node ]]; then
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>JSON.parse(s))' 2>/dev/null
  else
    printf '%s' "$1" | "$py" -c 'import json,sys;json.load(sys.stdin)' 2>/dev/null
  fi
}

pass=0 fail=0 skip=0
expect() { # allow|deny name payload [text the reason must contain]
  local want=$1 name=$2 payload=$3 needle=${4:-} out err rc got
  out=$(printf '%s' "$payload" | bash "$repo/scripts/agents-guard.sh" 2>"$tmp/err") rc=$?
  err=$(cat "$tmp/err")
  if [[ $payload == '{"toolCall"'* ]]; then
    if [[ $rc == 0 && -z $out ]]; then got=allow
    elif [[ $rc == 0 && $out == '{"decision":"deny","reason":'* ]] && valid_json "$out"; then got=deny err=$out
    else got="bad(rc=$rc out=$out)"; fi
  else
    if [[ $rc == 0 && -z $out ]]; then got=allow
    elif [[ $rc == 2 && -n $err ]]; then got=deny
    else got="bad(rc=$rc out=$out)"; fi
  fi
  if [[ $got == "$want" && ( $want == allow || -z $needle || $err == *"$needle"* ) ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL [%s] %s: want %s, got %s\n  %s\n' "$reader" "$name" "$want" "$got" "${err:0:300}"
  fi
}

A="$repo/AGENTS.md"
run_cases() {
  # Claude Code
  expect deny "claude edit inside shared block" "$(c_edit "$A" 'Rule one says alpha.' 'Rule one says gamma.')" "agents/AGENTS.shared.md"
  expect deny "claude edit names the specifics section" "$(c_edit "$A" 'Rule one says alpha.' 'x')" "## demo specifics"
  expect allow "claude edit in specifics" "$(c_edit "$A" 'Local rule says beta.' 'Local rule says gamma.')"
  expect deny "claude edit removes END marker" "$(c_edit "$A" '<!-- END SHARED -->' '')"
  expect deny "claude edit adds a second BEGIN marker in specifics" "$(c_edit "$A" 'Local rule says beta.' '<!-- BEGIN SHARED x -->')"
  expect allow "claude edit with old_string not in file" "$(c_edit "$A" 'not present' 'y')"
  expect deny "claude first-match edit lands in the block" "$(c_edit "$A" 'Same words here.' 'Changed.')"
  expect allow "claude multiedit in specifics" "$(c_multi "$A" 'Local rule says beta.' 'Local rule says b2.' 'Local rule says b2.' 'Local rule says b3.')"
  expect deny "claude multiedit second edit hits block" "$(c_multi "$A" 'Local rule says beta.' 'b' 'Rule one says alpha.' 'z')"
  expect deny "claude write changes the block" "$(c_write "$A" "# AGENTS.md: demo"$'\n\n'"${block_lines/alpha/omega}"$'\n\n## demo specifics\nNew.\n')"
  expect allow "claude write keeps the block" "$(c_write "$A" "# AGENTS.md: demo"$'\n\n'"$block_lines"$'\n\n## demo specifics\nRewritten specifics.\n')"
  expect deny "claude write drops the block" "$(c_write "$A" $'# AGENTS.md\n\nonly local\n')"
  expect deny "claude edit .claude/skills" "$(c_write "$repo/.claude/skills/x/SKILL.md" 'x')" ".agents/skills/x/"
  expect deny "claude edit shared skill" "$(c_edit "$repo/.agents/skills/create-pr/SKILL.md" 'x' 'y')" "PR to capstone-hpsi-2/.github"
  expect allow "claude edit repo-local skill" "$(c_edit "$repo/.agents/skills/local-bench/SKILL.md" 'x' 'y')"
  expect allow "claude create new repo-local skill" "$(c_write "$repo/.agents/skills/new-thing/SKILL.md" 'x')"
  expect deny "claude edit CLAUDE.md" "$(c_write "$repo/CLAUDE.md" $'@AGENTS.md\nAlso do X.\n')" "@AGENTS.md"
  expect deny "claude nested CLAUDE.md" "$(c_write "$repo/app/CLAUDE.md" 'x')"
  expect deny "claude create GEMINI.md" "$(c_write "$repo/GEMINI.md" 'x')" "AGENTS.md"
  expect deny "claude edit synced settings" "$(c_edit "$repo/.claude/settings.json" '{' '{ ')" "agents/claude/settings.json"
  expect deny "claude edit synced hooks.json" "$(c_write "$repo/.agents/hooks.json" '{}')"
  expect deny "claude edit guard script" "$(c_write "$repo/scripts/agents-guard.sh" 'exit 0')"
  expect allow "claude edit app/main.py" "$(c_write "$repo/app/main.py" 'print(1)')"
  expect allow "claude edit agents.lock.json" "$(c_edit "$repo/agents.lock.json" 'BOOTSTRAP' 'abc')"
  expect allow "claude file outside the repo" "$(c_write "$tmp/other/CLAUDE.md" 'x')"
  expect deny "claude relative path" "$(CWD=$repo c_edit 'AGENTS.md' 'Rule one says alpha.' 'q')"
  expect deny "claude dot-dot path" "$(c_write "$repo/app/../.claude/skills/x/SKILL.md" 'x')"
  expect deny "claude upper-case name" "$(c_write "$repo/claude.MD" 'x')"

  # Antigravity
  expect deny "ag replace inside block" "$(a_replace "$A" 'Rule one says alpha.' 'Rule one says beta.' 5 5)" "agents-md-placement"
  expect allow "ag replace in specifics" "$(a_replace "$A" 'Local rule says beta.' 'Local rule says z.' 10 10)"
  expect allow "ag replace same text, range in specifics" "$(a_replace "$A" 'Same words here.' 'Changed.' 11 11)"
  expect deny "ag replace same text, range in block" "$(a_replace "$A" 'Same words here.' 'Changed.' 6 6)"
  expect deny "ag replace with wrong range falls back to whole file" "$(a_replace "$A" 'Rule one says alpha.' 'q' 10 11)"
  expect allow "ag multi chunks in specifics" "$(a_multi "$A" 'Local rule says beta.' 'b2' 10 10 'Same words here.' 'c2' 11 11)"
  expect deny "ag multi one chunk in block" "$(a_multi "$A" 'Local rule says beta.' 'b2' 10 10 'Rule one says alpha.' 'c2' 5 5)"
  expect deny "ag write changes block" "$(a_write "$A" 'replaced')"
  expect allow "ag write keeps block" "$(a_write "$A" "# AGENTS.md: demo"$'\n\n'"$block_lines"$'\n\n## demo specifics\nNew.\n')"
  expect deny "ag edit .claude/skills" "$(a_write "$repo/.claude/skills/pr-review/SKILL.md" 'x')"
  expect deny "ag edit shared skill" "$(a_replace "$repo/.agents/skills/create-pr/SKILL.md" 'x' 'y' 1 1)"
  expect allow "ag edit repo-local skill" "$(a_replace "$repo/.agents/skills/local-bench/SKILL.md" 'x' 'y' 1 1)"
  expect deny "ag edit CLAUDE.md" "$(a_write "$repo/CLAUDE.md" 'x')"
  expect deny "ag create GEMINI.md" "$(a_write "$repo/GEMINI.md" 'x')"
  expect deny "ag edit hooks.json" "$(a_write "$repo/.agents/hooks.json" '{}')"
  expect allow "ag edit app/main.py" "$(a_write "$repo/app/main.py" 'x')"
  expect deny "ag relative path" "$(WS=$repo a_write 'CLAUDE.md' 'x')"
  expect deny "ag reason survives quotes and backslashes in the path" "$(a_write "$repo/.claude/skills/a\"b/SKILL.md" 'x')"

  # Windows path forms
  if [[ -n $winroot ]]; then
    local lowroot
    lowroot=$(printf '%s' "$winroot_fwd" | tr '[:upper:]' '[:lower:]')
    expect deny "win backslash path, block edit" "$(c_edit "$winroot\\AGENTS.md" 'Rule one says alpha.' 'q')"
    expect allow "win backslash path, specifics edit" "$(c_edit "$winroot\\AGENTS.md" 'Local rule says beta.' 'q')"
    expect deny "win forward-slash path, .claude/skills" "$(c_write "$winroot_fwd/.claude/skills/x/SKILL.md" 'x')"
    expect deny "win lower-case drive and dirs, CLAUDE.md" "$(c_write "$lowroot/CLAUDE.md" 'x')"
    expect deny "win upper-case file name AGENTS.MD" "$(c_edit "$winroot\\AGENTS.MD" 'Rule one says alpha.' 'q')"
    expect allow "win app file" "$(c_write "$winroot\\app\\main.py" 'x')"
    expect deny "win antigravity shared skill" "$(a_replace "$winroot\\.agents\\skills\\create-pr\\SKILL.md" 'x' 'y' 1 1)"
    expect deny "win antigravity relative path with workspace C:\\" "$(WS=$winroot a_write '.agents\hooks.json' '{}')"
    expect allow "win other drive" "$(c_write 'D:\elsewhere\CLAUDE.md' 'x')"
  else
    skip=$((skip + 9))
  fi
}

readers=() py=
for c in python3 python; do
  p=$(type -P "$c") && [[ $p != */WindowsApps/* ]] && "$p" -c 'import json' 2>/dev/null && { py=$p; break; }
done
[[ -n $py ]] && readers+=(python)
node -e '' 2>/dev/null && readers+=(node)
((${#readers[@]})) || { echo "need python or node" >&2; exit 1; }
for reader in "${readers[@]}"; do
  export AGENTS_GUARD_JSON=$reader
  run_cases
done

# The real launch path: Antigravity CLI splits the hooks.json command on spaces, runs it from
# .agents/ with no shell, and blocks the edit if the command itself fails.
reader=hooks.json
git init -q "$repo" && mkdir -p "$repo/.agents" && chmod +x "$repo/scripts/agents-guard.sh"
cmd=$(sed -n 's/^ *"command": "\(.*\)",\{0,1\}$/\1/p' "$here/../antigravity/hooks.json")
read -r -a argv <<<"$cmd"
launch() { (cd "$repo/.agents" && printf '%s' "$1" | "${argv[@]}"); }
out=$(launch "$(a_write "$repo/CLAUDE.md" 'x')" 2>&1) rc=$?
if [[ $rc == 0 && $out == '{"decision":"deny"'* ]]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL [hooks.json] '$cmd' must deny CLAUDE.md (rc=$rc out=${out:0:200})"
fi
out=$(launch "$(a_write "$repo/app/main.py" 'x')" 2>&1) rc=$?
if [[ $rc == 0 && -z $out ]]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL [hooks.json] '$cmd' must allow app/main.py (rc=$rc out=${out:0:200})"
fi

reader=none
out=$(printf '%s' "$(c_edit "$A" 'Rule one says alpha.' 'q')" | AGENTS_GUARD_JSON=none bash "$repo/scripts/agents-guard.sh" 2>"$tmp/err") rc=$?
if [[ $rc == 0 && -z $out ]] && grep -q 'no python or node' "$tmp/err"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL [none] no reader must allow with a warning (rc=$rc)"
fi

echo "readers: ${readers[*]}; passed $pass, failed $fail, skipped $skip"
((fail == 0))
