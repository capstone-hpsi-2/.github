#!/usr/bin/env bash
# PreToolUse hook for Claude Code (.claude/settings.json) and Antigravity (.agents/hooks.json).
# Synced from capstone-hpsi-2/.github agents/scripts/agents-guard.sh; change it there.
#
# Refuses agent edits to files that scripts/sync-agents.sh generates and says where the change
# belongs, so the agent moves the change to the right file instead of learning about it from CI.
# Only the agents' file tools reach this hook: sync-agents.sh, shell commands and humans are not
# stopped here, and `sync-agents.sh --check` in CI catches what gets past.
#
# Claude Code: a refusal exits 2 with the reason on stderr, which blocks even if stdout is not
# valid JSON. Antigravity: a refusal prints {"decision":"deny","reason":...}. An allowed edit prints
# nothing for either, so the host's own permission prompts still apply ("allow" would skip them).
#
# The repo is found from the edited file, not from this script's location: the nearest folder
# above it holding agents.lock.json. A session can edit another checkout, a Claude worktree under
# .claude/worktrees/, or a workspace opened through a junction or symlink, and each of those has
# its own AGENTS.md and lock. So any copy of this script guards any repo, which is what lets a
# user-level hook cover sessions started above the repos (agents/README.md in .github).
#
# Claude Code runs this in shell form through Git Bash. In exec form "bash" is looked up on the
# Windows PATH, where C:\Windows\System32\bash.exe (WSL) comes before Git's bash.
# Antigravity CLI (seen on 1.3.1, Windows) splits the hook command on spaces with no shell, runs
# it from the .agents/ folder, and blocks the edit when the command fails, so a "bash ..." command
# reached WSL bash or nothing. It runs this through a git alias instead: git is on every machine,
# runs "!" aliases with its own sh from the repo top level, and the command has no quoting. That
# needs the shebang and, outside Windows, the executable bit (sync-agents.sh sets it, --check
# verifies it).
#
# It runs before every agent file edit, and Git Bash pays roughly 100 ms per subprocess, so the
# only subprocess is the JSON reader; everything else is bash builtins (bash 4 or newer).
#
# AGENTS_GUARD_JSON=python|node|none forces the JSON reader; the tests use it to cover both.
# AGENTS_GUARD_SCOPE=user marks the user-level hook, which steps aside when the session's own
# project hook already runs, so an edit is not checked twice.
set -uo pipefail
# bash 5.2 turns "&" in a ${s/old/new} replacement into the matched text; edits must stay literal.
shopt -u patsub_replacement 2>/dev/null || true

caller_dir=$PWD
IFS= read -r -d '' input || true

# Bash cannot parse JSON and Git Bash has no jq. Backends have python, the frontend has node, so
# both readers exist and do the same thing: flatten the payload into NUL-separated
# "dotted.key" / value pairs. A NUL inside a value would shift every later key onto the wrong
# value and hide text from the checks, so it becomes U+FFFD.
PY='import json,sys
o=[]
def w(p,v):
    if isinstance(v,dict):
        for k in v: w(p+[k],v[k])
    elif isinstance(v,list):
        for i,x in enumerate(v): w(p+[str(i)],x)
    else: o.extend([".".join(p),v if isinstance(v,str) else json.dumps(v)])
w([],json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}"))
sys.stdout.buffer.write("".join(x.replace("\0","\ufffd")+"\0" for x in o).encode("utf-8"))'
JS='const o=[];const w=(p,v)=>{if(v!==null&&typeof v==="object"){for(const k of Object.keys(v))w(p.concat(k),v[k])}else o.push(p.join("."),typeof v==="string"?v:JSON.stringify(v))};
let s="";process.stdin.setEncoding("utf8");process.stdin.on("data",c=>s+=c).on("end",()=>{w([],JSON.parse(s||"{}"));process.stdout.write(o.map(x=>x.replace(/\0/g,"\ufffd")+"\0").join(""))})'

flatten() {
  local want=${AGENTS_GUARD_JSON:-auto} py
  if [[ $want == auto || $want == python ]]; then
    # python3 on stock Windows is a Microsoft Store stub that fails after about a second.
    for py in python3 python; do
      py=$(type -P "$py") || continue
      [[ $py == */WindowsApps/* ]] && continue
      printf '%s' "$input" | "$py" -c "$PY" 2>/dev/null && return 0
    done
  fi
  if [[ $want == auto || $want == node ]]; then
    printf '%s' "$input" | node -e "$JS" 2>/dev/null && return 0
  fi
  return 1
}

keys=() vals=()
while IFS= read -r -d '' k && IFS= read -r -d '' v; do keys+=("$k") vals+=("$v"); done < <(flatten)
if ((${#keys[@]} == 0)); then
  # Failing closed would block every edit on a machine without python or node, so this allows
  # and leaves the generated files to `sync-agents.sh --check` in CI.
  echo "agents-guard: no python or node could read the hook payload; edit allowed, CI checks it." >&2
  exit 0
fi

# Results go to REPLY, not stdout: a $(...) per lookup would cost a subprocess each.
has() { local i; for i in "${!keys[@]}"; do [[ ${keys[i]} == "$1" ]] && return 0; done; return 1; }
get() {
  local i
  REPLY=
  for i in "${!keys[@]}"; do [[ ${keys[i]} == "$1" ]] && { REPLY=${vals[i]//$'\r'/}; return 0; }; done
  return 1
}

if has tool_name; then
  host=claude args=tool_input proj=${CLAUDE_PROJECT_DIR:-} hookfile=.claude/settings.json
  get cwd; base=$REPLY
  get tool_input.file_path || get tool_input.notebook_path; file=$REPLY
elif has toolCall.name; then
  host=antigravity args=toolCall.args hookfile=.agents/hooks.json
  get workspacePaths.0; base=$REPLY proj=$REPLY
  get toolCall.args.TargetFile; file=$REPLY
else
  exit 0
fi
[[ -n $file ]] || exit 0

deny() {
  local msg="Blocked by scripts/agents-guard.sh. $1" s
  if [[ $host == claude ]]; then
    printf '%s\n' "$msg" >&2
    exit 2
  fi
  s=${msg//\\/\\\\} s=${s//\"/\\\"} s=${s//$'\n'/\\n} s=${s//$'\t'/\\t}
  printf '{"decision":"deny","reason":"%s"}\n' "$s"
  exit 0
}

# Turns a payload path into one this shell can open. Payloads carry C:\x, C:/x, /c/x (Git Bash),
# /mnt/c/x (WSL) or relative paths. Windows also opens a file through \\?\C:\x and through a
# stream name (AGENTS.md::$DATA is AGENTS.md), so both are reduced to the plain name.
# "." and ".." are resolved by name first, because a missing folder cannot be resolved on disk.
norm() {
  local p=${1//\\//} part out=() parts
  [[ $p == //[?.]/* ]] && p=${p:4}
  if [[ $p =~ ^([A-Za-z]):(/.*)?$ ]]; then
    p="/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
  fi
  IFS=/ read -r -a parts <<<"$p"
  for part in "${parts[@]}"; do
    part=${part%%:*}
    case $part in
      '' | .) ;;
      ..) ((${#out[@]})) && unset "out[$((${#out[@]} - 1))]" ;;
      *) out+=("$part") ;;
    esac
  done
  printf -v REPLY '/%s' "${out[@]}"
}

file=${file//\\//}
[[ $file == /* || $file =~ ^[A-Za-z]: ]] || file="${base:-$caller_dir}/$file"
norm "$file"
# The deepest folder that exists is resolved on disk (cd -P), so a junction or symlink becomes
# the real path; the part that does not exist yet (a new file or folder) is appended by name.
dir=${REPLY%/*} tail=${REPLY##*/}
while [[ -n $dir && ! -d $dir ]]; do tail=${dir##*/}/$tail dir=${dir%/*}; done
cd -P "${dir:-/}" 2>/dev/null || exit 0
dir=${PWD%/}
path=$dir/$tail
# A .git without a lock is a repo that does not use the shared agent files: nothing to guard.
while [[ ! -f $dir/agents.lock.json ]]; do
  [[ -e $dir/.git || -z $dir ]] && exit 0
  dir=${dir%/*}
done
root=$dir
rel=${path#"$root"/}
r=${rel,,}

if [[ ${AGENTS_GUARD_SCOPE:-} == user && -n $proj ]]; then
  norm "$proj"
  [[ -f $REPLY/$hookfile && -f $REPLY/scripts/agents-guard.sh ]] && exit 0
fi

SRC='capstone-hpsi-2/.github'
UNSURE='Unsure where it goes: load skill agents-md-placement.'
RULES_HOME="Put the rule in AGENTS.md: shared rules by PR to $SRC agents/AGENTS.shared.md, repo rules in the '## ... specifics' section of this repo's AGENTS.md. $UNSURE"

shared=" "
lock=
IFS= read -r -d '' lock <"$root/agents.lock.json" 2>/dev/null
re='"skills"[[:space:]]*:[[:space:]]*\[([^]]*)\]'
if [[ $lock =~ $re ]]; then
  list=${BASH_REMATCH[1]//[^A-Za-z0-9_-]/ }
  for s in $list; do shared+="${s,,} "; done
fi

case $r in
  .claude/skills/*)
    name=${r#.claude/skills/} name=${name%%/*}
    if [[ $shared == *" $name "* ]]; then
      deny ".claude/skills/$name/ is a generated copy of the shared skill $name (Claude Code reads skills only from .claude/skills). Change the skill with a PR to $SRC editing agents/skills/$name/SKILL.md; the chore/sync-agents PR brings it to this repo. For a procedure only this repo needs, create a repo-local skill under a new name in .agents/skills/<new-name>/SKILL.md, then run: bash scripts/sync-agents.sh. $UNSURE"
    fi
    deny ".claude/skills/ is a generated copy of .agents/skills/ (Claude Code reads skills only from .claude/skills). Edit .agents/skills/$name/ instead, then run: bash scripts/sync-agents.sh, which rebuilds the copy. $UNSURE"
    ;;
  .claude/settings.json | .agents/hooks.json | scripts/agents-guard.sh | scripts/sync-agents.sh)
    deny "$rel is synced from $SRC agents/ by scripts/sync-agents.sh and is the same in every repo. Change it with a PR to $SRC (layout in agents/README.md there). Personal Claude Code settings go in .claude/settings.local.json, which is not committed."
    ;;
  agents.lock.json)
    deny "agents.lock.json is written by scripts/sync-agents.sh: its skills list decides which skills this guard treats as shared. To adopt newer shared files run: bash scripts/sync-agents.sh --latest. In a rebase conflict, take main's pin with: git checkout --ours agents.lock.json, then run: bash scripts/sync-agents.sh."
    ;;
  .github/workflows/agents.yml)
    deny ".github/workflows/agents.yml is the same in every repo; its source is $SRC agents/workflows/agents.yml. Change it with a PR there; the chore/sync-agents PR brings it here (with the SYNC_TOKEN secret; without it, run bash scripts/sync-agents.sh on your machine)."
    ;;
  claude.md | */claude.md)
    deny "CLAUDE.md contains only the line @AGENTS.md (shared guardrail 8), so Claude Code and Antigravity read the same rules. $RULES_HOME"
    ;;
  gemini.md | */gemini.md)
    deny "There is no GEMINI.md: Antigravity reads AGENTS.md (shared guardrail 8). $RULES_HOME"
    ;;
  .agents/skills/*/*)
    name=${r#.agents/skills/} name=${name%%/*}
    if [[ $shared == *" $name "* ]]; then
      deny ".agents/skills/$name/ is a shared skill, copied from $SRC agents/skills/$name/; local edits are overwritten by the next sync. Change it with a PR to $SRC. For a procedure only this repo needs, create a repo-local skill under a new name in .agents/skills/<new-name>/SKILL.md. $UNSURE"
    fi
    exit 0
    ;;
  .claude/rules/* | .agents/rules/* | .agent/rules/* | */agents.md | claude.local.md | */claude.local.md)
    deny "$rel would be a second home for agent rules that only one of Claude Code and Antigravity reads (shared guardrail 8). $RULES_HOME Personal notes go in your user-level ~/.claude/CLAUDE.md, outside the repo."
    ;;
  agents.md) ;;
  *) exit 0 ;;
esac

# AGENTS.md: allowed unless the edit changes the shared block. The signature is every line from a
# BEGIN SHARED marker through its END SHARED marker, plus the marker counts.
signature() {
  local line inb=0 nb=0 ne=0 sig=
  while IFS= read -r line; do
    [[ $line == '<!-- BEGIN SHARED'* ]] && { nb=$((nb + 1)) inb=1; }
    ((inb)) && sig+=$line$'\n'
    [[ $line == '<!-- END SHARED'* ]] && { ne=$((ne + 1)) inb=0; }
  done <<<"$1"
  REPLY="$sig markers $nb $ne"
}

replace() { # text old new all
  if [[ -z $2 ]]; then REPLY=$1
  elif [[ $4 == true ]]; then REPLY=${1//"$2"/"$3"}
  else REPLY=${1/"$2"/"$3"}; fi
}

# Antigravity edits name a 1-based line range that must contain the target text. When the range
# is missing, odd, or does not contain the text, every occurrence in the file is replaced: that
# can refuse an edit that was fine, never allow one that was not.
replace_in_range() { # text old new all start end
  local s=$5 e=$6 n=0 line pre= mid= post=
  if [[ $s =~ ^[0-9]+$ && $e =~ ^[0-9]+$ ]] && ((s >= 1 && e >= s)); then
    while IFS= read -r line; do
      n=$((n + 1))
      if ((n < s)); then pre+=$line$'\n'; elif ((n <= e)); then mid+=$line$'\n'; else post+=$line$'\n'; fi
    done <<<"$1"
    if [[ -n $2 && $mid == *"$2"* ]]; then
      replace "$mid" "$2" "$3" "$4"
      REPLY=$pre$REPLY$post
      return
    fi
  fi
  replace "$1" "$2" "$3" true
}

old=
IFS= read -r -d '' old <"$root/AGENTS.md" 2>/dev/null
# A CRLF checkout must compare equal to the LF text in payloads.
old=${old//$'\r'/}
signature "$old"; before=$REPLY
spec=
re=$'(^|\n)## ([^\n]* specifics)[[:space:]]*(\n|$)'
[[ $old =~ $re ]] && spec=${BASH_REMATCH[2]}
BLOCK_MSG="This edit changes the shared block of AGENTS.md (from the <!-- BEGIN SHARED line to <!-- END SHARED -->). scripts/sync-agents.sh copies that block from $SRC agents/AGENTS.shared.md and overwrites local changes. Put the change here instead: a rule for every repo goes in a PR to $SRC editing agents/AGENTS.shared.md; a rule for this repo only goes in the '## ${spec:-<repo> specifics}' section below <!-- END SHARED -->; a multi-step procedure goes in a repo-local skill, .agents/skills/<new-name>/SKILL.md. To restore the block, or to resolve a merge conflict inside it, run: bash scripts/sync-agents.sh. $UNSURE"
# Claude Code's Edit also matches text that differs from the file (curly for straight quotes, at
# least), so a string this hook cannot find could still land in the block. Unknown text is
# refused; the agent's retry with the exact text costs one turn.
NOMATCH_MSG="The text to replace is not in AGENTS.md exactly as written (quotes, spaces and line breaks must match), so this hook cannot tell whether the edit touches the shared block. Read AGENTS.md and copy the text exactly."

check() { signature "$1"; [[ $REPLY == "$before" ]] || deny "$BLOCK_MSG"; }
edit() { # key prefix holding old/new/all fields; applies to $after
  local o n a
  get "$1.$2"; o=$REPLY
  get "$1.$3"; n=$REPLY
  get "$1.$4"; a=$REPLY
  [[ -z $o || $after == *"$o"* ]] || deny "$NOMATCH_MSG"
  replace "$after" "$o" "$n" "$a"; after=$REPLY
}

if [[ $host == claude ]]; then
  if get "$args.content"; then
    check "$REPLY"
    exit 0
  fi
  after=$old
  # MultiEdit applies its edits in order, each to the result of the previous one.
  i=0
  while has "$args.edits.$i.old_string"; do
    edit "$args.edits.$i" old_string new_string replace_all
    i=$((i + 1))
  done
  has "$args.old_string" && edit "$args" old_string new_string replace_all
  check "$after"
  exit 0
fi

if get "$args.CodeContent"; then
  check "$REPLY"
  exit 0
fi
# Chunks address lines of the original file and do not overlap, so each is checked on its own
# against the original: the block changes only if some chunk changes it.
chunk() {
  local t c a s e
  get "$1.TargetContent"; t=$REPLY
  get "$1.ReplacementContent"; c=$REPLY
  get "$1.AllowMultiple"; a=$REPLY
  get "$1.StartLine"; s=$REPLY
  get "$1.EndLine"; e=$REPLY
  [[ -z $t || $old == *"$t"* ]] || deny "$NOMATCH_MSG"
  replace_in_range "$old" "$t" "$c" "$a" "$s" "$e"
  check "$REPLY"
}
has "$args.TargetContent" && chunk "$args"
i=0
while has "$args.ReplacementChunks.$i.TargetContent"; do
  chunk "$args.ReplacementChunks.$i"
  i=$((i + 1))
done
exit 0
