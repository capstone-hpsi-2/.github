---
name: create-pr
description: Use before the first edit whenever you or the user start creating, changing, fixing or editing a feature, or any code, config or docs, in admin-backend, transcription-backend, frontend or .github, and again to finish it. Every change reaches main only through a PR from a feat/<member>-<featname> branch, so this covers the whole path - start or resume the branch, rebase on origin/main, run the repo gate, run the adversarial self-review with subagents, push and gh pr create. Also for "start a feature", "fix this", "change X", "new branch", "continue my branch", "rebase on main", "open a PR", "push my work". Not for reviewing someone else's PR (use pr-review).
---

# Create PR

Every change, however small, goes start (or continue) then finish. Run Start or Continue before the first edit, not after.

Commands are Bash and run in Git Bash on Windows and on Linux. On Windows use `python`, not `python3` (often a Store stub).

## Stop rules (check every time)
Refuse and explain if the next step would:
- commit or push while on `main`, a detached HEAD, `chore/sync-agents` or `chore/sync-contracts` (owned by the sync jobs),
- push to `main` in any form,
- use `--no-verify`, or `--force` without `--with-lease`.

```bash
b=$(git branch --show-current); [[ -z $b || $b == main || $b == chore/sync-* ]] && echo "STOP: switch to a feature branch"
```

## Start
1. Ask which member is working (list in `AGENTS.md` guardrail 2) and the feature name.
2. Tree must be clean: `git status --porcelain` prints nothing. Else, on `main`: do step 4 now (`git checkout -b` carries the uncommitted changes onto the new branch), commit them there and skip step 3; Finish rebases on `origin/main`. Elsewhere: commit or stash.
3. Update main: `git fetch origin --prune && git checkout main && git pull --ff-only origin main`. If `--ff-only` fails, someone committed on local `main`: stop and tell the user.
4. Create the branch and check its name:
   ```bash
   b=feat/jered-claim-long-poll
   [[ $b =~ ^feat/[a-z]+-[a-z0-9]+(-[a-z0-9]+)*$ ]] && git checkout -b "$b"
   ```

## Continue
1. `git fetch origin --prune && git checkout <branch>` (only on the remote: `git checkout --track origin/<branch>`).
2. Stash local changes if any, then `git rebase origin/main`.
3. On conflict: keep both intents. Never hand-merge generated files: take main's side (in a rebase `--ours` is main), regenerate, continue. The `chore/sync-agents` and `chore/sync-contracts` PRs touch these files often.
   ```bash
   # agent files: the sync rewrites every generated file, conflicted ones included
   git checkout --ours agents.lock.json .claude/skills && bash scripts/sync-agents.sh
   # frontend contracts
   git checkout --ours contracts.lock.json contracts src/api/generated && GITHUB_TOKEN=$(gh auth token) ./scripts/sync-contracts.sh
   # backend spec
   python -m app.export_openapi
   git add <the conflicted paths> && git rebase --continue
   ```
   If your branch changed a lock on purpose, re-apply that change before the sync. If you do not understand the other side, `git rebase --abort` and ask its author (`git log origin/main -- <file>`).
4. Run the gate before writing new code so you know the base is green.

## Finish (before every PR, in order)
1. Rebase again: `git fetch origin --prune && git rebase origin/main`. A gate run before this does not count.
2. Run the repo gate and the `all` row from the "Gates" table in `AGENTS.md`. Keep the output. Red gate: fix, commit, rerun.
   A backend change to `openapi/*.yaml` also typechecks the frontend against it, since the PR's `contract-frontend` check runs the same. Needs sibling checkouts `../frontend` (clean, on current `main`, `npm ci` done) and the other backend:
   ```bash
   (cd ../frontend && if [[ -n $(git status --porcelain) ]]; then echo "STOP: ../frontend has local changes"; else
     ./scripts/sync-contracts.sh --local && npm run typecheck; rc=$?; git checkout -- contracts src/api/generated; exit $rc; fi)
   ```
   Red: the change breaks the frontend. Coordinate a frontend PR and link it in this PR.
3. Adversarial self-review. Spawn 4 subagents in parallel, fresh context each, one lens each, none seeing the others' output:

   | Lens | Looks for |
   |---|---|
   | Correctness | wrong logic, edge cases, races (give the interleaving), tests that do not test the claim |
   | Security / privacy | missing auth or access checks, JWT checks, clinical data in logs, fixtures, errors or outbound requests, secrets |
   | Contracts / compat | OpenAPI and `app/contracts` changes, old clients and rows, Alembic up and down, design rules the change touches |
   | Resources | heavy imports or whole-file reads in the API, unbounded queries, shared GPU memory, unmeasured numbers |

   Prompt each one:
   ```text
   Adversarial reviewer for repo [repo], branch [b], lens [lens]. Run `git diff origin/main...HEAD`,
   read every changed file in full and AGENTS.md. Prove the change is wrong, unsafe or incomplete
   under your lens. No praise. Per finding: P0 (blocks merge) / P1 (must fix) / P2 (note), file:line,
   a concrete failing scenario, a fix. If nothing, list what you tried and why it held. Do not edit files.
   ```
   Fix each finding (then rerun step 2) or answer it in one line. An open P0 blocks the PR. No subagents available: run each lens in a separate fresh session, never in the context that wrote the code.
4. Cascade: update the one home of any fact you changed and grep for stale mentions (`AGENTS.md`, "Cascade"). Also run any repo-specific checks in that repo's `AGENTS.md`.
5. Push: `git push -u origin HEAD`, or after rebasing a pushed branch `git push --force-with-lease origin HEAD`. A 403 means no write access to the repo: ask an org owner for it, do not work around it.
6. Write the PR body to `.git/PR_BODY.md` with a file-writing tool (not a heredoc), then:
   ```bash
   gh pr create --base main --head "$b" --title "worker: claim jobs with long-poll" --body-file .git/PR_BODY.md
   ```
   Title `<area>: <imperative>`, under 70 characters. Body: every section of the PR template (the repo's `.github/PULL_REQUEST_TEMPLATE.md`, else the org default in `capstone-hpsi-2/.github`), plus three it does not have: `## Gate (after rebase on origin/main <short sha>)`, `## Adversarial self-review` with a `| Lens | Findings | Outcome |` table, and `## Repo-specific checks` (from the repo `AGENTS.md`). Every section filled; "n/a" needs a reason. Return the PR URL and remind the user another member must review before merge.
