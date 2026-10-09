#!/usr/bin/env bash
# Copies the shared agent files from capstone-hpsi-2/.github agents/ at the commit pinned in
# agents.lock.json. What lands where: agents/README.md in that repo. This script is one of those
# files, so change it there.
#
#   bash scripts/sync-agents.sh                   sync from the pinned sha on GitHub
#   bash scripts/sync-agents.sh --local <path>    sync from a local checkout of capstone-hpsi-2/.github
#   bash scripts/sync-agents.sh --latest          pin the newest sha of .github main, then sync
#   bash scripts/sync-agents.sh --check           fail if anything differs from the pin; writes nothing
#   bash scripts/sync-agents.sh --latest --check  drift probe against newest main; writes nothing
#
# The agent hooks refuse edits to the generated files, but this script runs as a plain process, not
# through an agent's file tools, so the hooks never see it.
#
# The whole script is one { } block, so bash parses all of it before running any of it. The sync
# replaces this file, and bash otherwise keeps reading a running script from disk as it goes.
{
set -euo pipefail
# Glob order becomes the order of the lock's skills list, which --check compares as text; C
# collation makes it the same on every machine.
export LC_COLLATE=C

BEGIN_MARKER='<!-- BEGIN SHARED (synced from capstone-hpsi-2/.github agents/AGENTS.shared.md; do not edit here) -->'
END_MARKER='<!-- END SHARED -->'
SRC_SKILLS=.agents/skills
MIRROR=.claude/skills
GUARD=scripts/agents-guard.sh
# <path under the source agents/>:<path in this repo>
SYNCED_FILES=(
  claude/settings.json:.claude/settings.json
  antigravity/hooks.json:.agents/hooks.json
  scripts/agents-guard.sh:$GUARD
  scripts/sync-agents.sh:scripts/sync-agents.sh
)
# Copied only when run outside GitHub Actions: GITHUB_TOKEN may not push workflow files, so the
# daily sync PR would fail to push. --check only warns about it for the same reason.
WORKFLOW=workflows/agents.yml:.github/workflows/agents.yml
# Agent files that only one of Claude Code and Antigravity reads (shared guardrail 8).
RULE_FILES_RE='^(\.claude/rules/|\.agents/rules/|\.agent/rules/)|/(agents|claude|gemini)\.md$|(^|/)claude\.local\.md$'

MODE=github CHECK=false LATEST=false LOCAL_PATH=
while (($#)); do
  case "$1" in
    --local)
      [[ $# -ge 2 && $2 != --* ]] || { echo "--local needs a path, e.g. --local ../.github" >&2; exit 2; }
      # Resolved before the cd to the repo root, so a relative path means the caller's cwd.
      MODE=local LOCAL_PATH=$(cd "$2" 2>/dev/null && pwd) || { echo "error: $2 is not a directory" >&2; exit 2; }
      shift ;;
    --latest) LATEST=true ;;
    --check) CHECK=true ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
if [[ $MODE == local ]] && $LATEST; then
  echo "--local and --latest conflict: --local uses whatever the checkout has." >&2; exit 2
fi
cd "$(dirname "$0")/.."

# Backends have python but no node, the frontend has node, Git Bash has no jq. python3 on stock
# Windows is a Store stub that exits non-zero, so python is tried next. Windows python writes CRLF.
read_lock() {
  local py='import json;d=json.load(open("agents.lock.json"));print("\t".join([d["repo"],d["sha"],d["path"]," ".join(d.get("skills",[]))]))'
  local js='const d=require("./agents.lock.json");console.log([d.repo,d.sha,d.path,(d.skills||[]).join(" ")].join("\t"))'
  { python3 -c "$py" 2>/dev/null || python -c "$py" 2>/dev/null || node -e "$js"; } | tr -d '\r'
}
[[ -f agents.lock.json ]] || { echo "error: agents.lock.json not found in $(pwd)" >&2; exit 1; }
if grep -q '^<<<<<<<' agents.lock.json; then
  echo "error: agents.lock.json has merge conflict markers. Take main's pin first:" >&2
  echo "  git checkout --ours agents.lock.json   (in a rebase, --ours is main), then rerun this script" >&2
  exit 1
fi
lock=$(read_lock) || { echo "error: could not parse agents.lock.json (needs python or node)" >&2; exit 1; }
IFS=$'\t' read -r repo sha subdir pinned_skills <<<"$lock"

# These values become a URL, paths and rm -rf targets, so "../.." in the lock must not get through.
CANON_REPO=capstone-hpsi-2/.github
NAME_RE='^[a-z0-9][a-z0-9-]*$'
[[ $repo =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || { echo "error: bad repo '$repo' (want owner/name)" >&2; exit 1; }
[[ $subdir =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]] || { echo "error: bad path '$subdir' (one folder name)" >&2; exit 1; }
for name in $pinned_skills; do
  [[ $name =~ $NAME_RE ]] || { echo "error: bad skill name '$name' in agents.lock.json (kebab-case)" >&2; exit 1; }
done

if $LATEST; then
  # ls-remote uses smart HTTP: no API rate limit, no JSON.
  sha=$(git ls-remote "https://github.com/$repo.git" refs/heads/main | cut -f1)
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "error: could not resolve main of $repo (got '$sha')" >&2; exit 1; }
  echo "• $repo main is at $sha"
fi

if [[ $MODE == github ]]; then
  if [[ $sha == BOOTSTRAP ]]; then
    echo "error: agents.lock.json has sha \"BOOTSTRAP\": the shared rules are not on .github main yet." >&2
    echo "  Use bash scripts/sync-agents.sh --local ../.github, or --latest once agents/ is merged." >&2
    exit 1
  fi
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "error: sha must be a full 40-char commit, got '$sha'" >&2; exit 1; }
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ $MODE == github ]]; then
  # A fork repo is for a laptop before the .github PR merges. In CI it would let a PR that only
  # edits agents.lock.json load rules from anyone's fork.
  if [[ $repo != "$CANON_REPO" && -n ${CI:-} ]]; then
    echo "error: CI accepts only repo $CANON_REPO in agents.lock.json, got '$repo'." >&2; exit 1
  fi
  # codeload serves any commit in the fork network, so a sha alone proves nothing. Requiring it
  # on main means only merged (reviewed) rules can be pinned. tree:0 fetches commits only.
  if [[ $repo == "$CANON_REPO" ]] && ! $LATEST; then
    git clone -q --bare --filter=tree:0 --single-branch --branch main "https://github.com/$repo.git" "$work/g" \
      || { echo "error: could not fetch main of $repo" >&2; exit 1; }
    git -C "$work/g" merge-base --is-ancestor "$sha" main 2>/dev/null \
      || { echo "error: $sha is not on $repo main. Pin a merged commit (--latest)." >&2; exit 1; }
  fi
fi

if [[ $MODE == local ]]; then
  src="$LOCAL_PATH/$subdir"
  [[ -d $src ]] || { echo "error: $src does not exist" >&2; exit 1; }
  pin=$src
else
  # One tarball, not one API call per file: the API allows 60 anonymous calls an hour per IP.
  pin="$repo@$sha"
  code=$(curl -sSL -w '%{http_code}' "https://codeload.github.com/$repo/tar.gz/$sha" -o "$work/src.tgz")
  [[ $code == 200 ]] || { echo "error: HTTP $code fetching $pin (404: commit not pushed to that repo)" >&2; exit 1; }
  mkdir -p "$work/tree"
  tar -xzf "$work/src.tgz" -C "$work/tree" --strip-components=1
  src="$work/tree/$subdir"
fi
echo "• agents <- $pin"

[[ -f $src/AGENTS.shared.md ]] || { echo "error: $subdir/AGENTS.shared.md missing at the source" >&2; exit 1; }
# Every source skill folder is shared. Taking the list from the source, not from the lock, is what
# lets the daily sync pick up a new, renamed or removed shared skill with no hand edit here.
skills=
for dir in "$src/skills"/*/; do
  [[ -d $dir ]] || continue
  name=$(basename "$dir")
  [[ $name =~ $NAME_RE ]] || { echo "error: bad skill folder '$name' at the source (kebab-case)" >&2; exit 1; }
  [[ -f $dir/SKILL.md ]] || { echo "error: $subdir/skills/$name/SKILL.md missing at the source" >&2; exit 1; }
  skills+="${skills:+ }$name"
done
# A skill leaves the repos when the lock still lists it, or when the source's skills-retired names
# it. The second covers a lock that was already rewritten (by hand or by a template) before the
# old folder was removed: the lock no longer remembers it, so only the source can.
stale=
retired=
if [[ -f $src/skills-retired ]]; then
  while IFS= read -r name; do
    name=${name%%#*} name=${name//[[:space:]]/}
    [[ -n $name ]] || continue
    [[ $name =~ $NAME_RE ]] || { echo "error: bad name '$name' in $subdir/skills-retired" >&2; exit 1; }
    retired+="${retired:+ }$name"
  done < <(tr -d '\r' <"$src/skills-retired")
fi
for name in $pinned_skills $retired; do
  [[ " $skills " == *" $name "* || " $stale " == *" $name "* ]] || stale+="${stale:+ }$name"
done
for entry in "${SYNCED_FILES[@]}"; do
  [[ -f $src/${entry%%:*} ]] || { echo "error: $subdir/${entry%%:*} missing at the source" >&2; exit 1; }
done

# CR stripped from text files only; grep -I skips binaries such as images.
to_lf() { find "$@" -type f -exec grep -Il . {} + 2>/dev/null | while IFS= read -r f; do sed -i 's/\r$//' "$f"; done; }

# Render the expected state into $work/out. --check compares it and writes nothing, so a failed
# check never leaves a half-synced repo.
out="$work/out"
mkdir -p "$out/skills" "$out/files"

[[ -f AGENTS.md ]] || { echo "error: AGENTS.md not found. Commit it with the two SHARED markers first." >&2; exit 1; }
# Matching by prefix catches a hand-edited or duplicated marker.
nb=$(tr -d '\r' <AGENTS.md | grep -c '^<!-- BEGIN SHARED' || true)
ne=$(tr -d '\r' <AGENTS.md | grep -c '^<!-- END SHARED' || true)
if [[ $nb != 1 || $ne != 1 ]]; then
  echo "error: AGENTS.md needs exactly one BEGIN SHARED and one END SHARED line (found $nb / $ne):" >&2
  printf '  %s\n  %s\n' "$BEGIN_MARKER" "$END_MARKER" >&2
  exit 1
fi
tr -d '\r' <"$src/AGENTS.shared.md" | awk '{ l[NR]=$0 } END { n=NR; while (n>0 && l[n] ~ /^[[:space:]]*$/) n--; for (i=1;i<=n;i++) print l[i] }' >"$work/shared.md"
tr -d '\r' <AGENTS.md | awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" -v f="$work/shared.md" '
  /^<!-- BEGIN SHARED/ { print b; while ((getline line < f) > 0) print line; skip=1; seen=1; next }
  /^<!-- END SHARED/   { if (!seen) { bad=1; exit } print e; skip=0; next }
  !skip { print }
  END { if (bad) exit 3 }
' >"$out/AGENTS.md" || { echo "error: END SHARED comes before BEGIN SHARED in AGENTS.md" >&2; exit 1; }

# Expected .agents/skills: the repo-local skills as they are, shared ones replaced from the pin,
# skills that left the source removed.
[[ -d $SRC_SKILLS ]] && cp -R "$SRC_SKILLS/." "$out/skills/"
for name in $stale; do rm -rf "${out:?}/skills/$name"; done
for name in $skills; do
  rm -rf "${out:?}/skills/$name"
  cp -R "$src/skills/$name" "$out/skills/$name"
done
for entry in "${SYNCED_FILES[@]}" "$WORKFLOW"; do
  [[ -f $src/${entry%%:*} ]] || continue
  mkdir -p "$out/files/$(dirname "${entry#*:}")"
  cp "$src/${entry%%:*}" "$out/files/${entry#*:}"
done
to_lf "$out/skills" "$out/files"

# Antigravity starts the guard as an executable (see its header), so on Linux and macOS a guard
# committed as 100644 blocks every Antigravity edit. Windows clones ignore the bit, so only the
# index shows it.
guard_mode=$(git ls-files -s -- "$GUARD" 2>/dev/null | cut -d' ' -f1 || true)
MODE_FIX="git add --chmod=+x $GUARD"

if $CHECK; then
  drift=()
  diff -q --strip-trailing-cr "$out/AGENTS.md" AGENTS.md >/dev/null 2>&1 || drift+=("AGENTS.md shared block")
  for name in $skills; do
    diff -rq --strip-trailing-cr "$out/skills/$name" "$SRC_SKILLS/$name" >/dev/null 2>&1 || drift+=("$SRC_SKILLS/$name/")
  done
  for name in $stale; do
    [[ ! -e $SRC_SKILLS/$name && ! -e $MIRROR/$name ]] || drift+=("skill $name is no longer shared; the sync removes it")
  done
  [[ $pinned_skills == "$skills" ]] || drift+=("agents.lock.json skills [$pinned_skills], source has [$skills]")
  for entry in "${SYNCED_FILES[@]}"; do
    diff -q --strip-trailing-cr "$out/files/${entry#*:}" "${entry#*:}" >/dev/null 2>&1 || drift+=("${entry#*:}")
  done
  [[ -z $guard_mode || $guard_mode == 100755 ]] || drift+=("$GUARD is committed as $guard_mode, needs 100755: $MODE_FIX")
  # The mirror must equal .agents/skills as committed, repo-local skills included.
  diff -rq --strip-trailing-cr "$SRC_SKILLS" "$MIRROR" >"$work/mirror.diff" 2>&1 || drift+=("$MIRROR/ is not a copy of $SRC_SKILLS/")
  [[ "$(tr -d '\r' <CLAUDE.md 2>/dev/null | sed '/^[[:space:]]*$/d')" == "@AGENTS.md" ]] || drift+=("CLAUDE.md must contain only @AGENTS.md")
  [[ ! -e GEMINI.md ]] || drift+=("GEMINI.md must not exist (rules live in AGENTS.md)")
  # Tracked files only: a personal, gitignored CLAUDE.local.md is not the repo's business.
  while IFS= read -r f; do
    drift+=("$f must not exist: agent rules live in AGENTS.md (shared guardrail 8)")
  done < <(git ls-files 2>/dev/null | grep -iE "$RULE_FILES_RE" | grep -viE '^\.(agents|claude)/skills/' || true)
  wf=${WORKFLOW#*:}
  if [[ -f $out/files/$wf ]] && ! diff -q --strip-trailing-cr "$out/files/$wf" "$wf" >/dev/null 2>&1; then
    echo "note: $wf differs from the source. Run bash scripts/sync-agents.sh on your machine (not CI) and commit it." >&2
  fi
  if ((${#drift[@]})); then
    echo "Agent files differ from $pin:" >&2
    printf '  %s\n' "${drift[@]}" >&2
    # head closing early kills sed with SIGPIPE; without || true, pipefail and set -e would exit
    # here and skip the how-to-fix lines below.
    sed 's/^/    /' "$work/mirror.diff" | head -n 20 >&2 || true
    diff -u --strip-trailing-cr --label "AGENTS.md (committed)" --label "AGENTS.md (expected)" AGENTS.md "$out/AGENTS.md" 2>/dev/null | head -n 40 >&2 || true
    if $LATEST; then
      echo "Upstream moved. The daily agents workflow opens a chore/sync-agents PR, or run" >&2
      echo "bash scripts/sync-agents.sh --latest on a feat/ branch and commit the result." >&2
    else
      echo "These files are generated (list: Generated files in AGENTS.md). Change shared files by PR" >&2
      echo "to capstone-hpsi-2/.github agents/, repo-local skills in $SRC_SKILLS/, repo rules in the" >&2
      echo "AGENTS.md specifics section. Then run bash scripts/sync-agents.sh and commit the result." >&2
    fi
    exit 1
  fi
  echo "Agent files match $pin."
  exit 0
fi

cp "$out/AGENTS.md" AGENTS.md
echo "    AGENTS.md shared block rewritten"
mkdir -p "$SRC_SKILLS"
for name in $stale; do
  [[ -e $SRC_SKILLS/$name ]] || continue
  rm -rf "${SRC_SKILLS:?}/$name"
  echo "    removed $SRC_SKILLS/$name (no longer shared)"
done
for name in $skills; do
  rm -rf "${SRC_SKILLS:?}/$name"
  cp -R "$out/skills/$name" "$SRC_SKILLS/$name"
done
to_lf "$SRC_SKILLS"
echo "    shared skills -> $SRC_SKILLS: $skills"
rm -rf "${MIRROR:?}"
mkdir -p "$(dirname "$MIRROR")"
cp -R "$SRC_SKILLS" "$MIRROR"
echo "    $MIRROR mirrored from $SRC_SKILLS"
files=("${SYNCED_FILES[@]}")
[[ -n ${GITHUB_ACTIONS:-} ]] || files+=("$WORKFLOW")
for entry in "${files[@]}"; do
  dest=${entry#*:}
  [[ -f $out/files/$dest ]] || continue
  mkdir -p "$(dirname "$dest")"
  # A temp file renamed into place, so the running copy of this script is never half-written.
  cp "$out/files/$dest" "$dest.sync-tmp"
  [[ $dest == *.sh ]] && chmod +x "$dest.sync-tmp"
  mv -f "$dest.sync-tmp" "$dest"
  echo "    $dest"
done
if [[ -n $guard_mode && $guard_mode != 100755 ]]; then
  echo "    note: $GUARD is staged as $guard_mode; run: $MODE_FIX" >&2
fi
if [[ ! -e CLAUDE.md ]]; then
  printf '@AGENTS.md\n' >CLAUDE.md
  echo "    CLAUDE.md created"
fi

# Last, so a failed step never leaves the lock pointing at content that was not synced.
# The skills list stays on one line so this sed can rewrite it.
list=
for name in $skills; do list+="${list:+, }\"$name\""; done
sed -i -E "s/(\"skills\"[[:space:]]*:[[:space:]]*)\[[^]]*\]/\1[$list]/" agents.lock.json
$LATEST && sed -i -E "s/(\"sha\"[[:space:]]*:[[:space:]]*\")[^\"]*\"/\1$sha\"/" agents.lock.json
lock=$(read_lock) || { echo "error: agents.lock.json no longer parses after the update" >&2; exit 1; }
IFS=$'\t' read -r _ new_sha _ new_skills <<<"$lock"
[[ $new_skills == "$skills" ]] || {
  echo "error: could not write the skills list into agents.lock.json; keep \"skills\": [...] on one line" >&2
  exit 1
}
echo "    agents.lock.json sha $new_sha, skills [$skills]"
exit 0
}
