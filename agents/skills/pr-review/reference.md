# PR review: method, structure, checklist

## Inputs
- The PR, its body and linked issue.
- The design it implements: the issue, `transcription-backend/docs/DESIGN.md`, the OpenAPI/AsyncAPI files. Nothing linked: ask the author, review against `AGENTS.md` meanwhile.

## Method (state it at the top of the report)
1. Check out the branch, note the merge base.
2. Read every non-generated changed file end to end, not just the hunks. Generated files (`openapi/openapi.yaml`, frontend `contracts/` and `src/api/generated/`, the synced `AGENTS.md` block, `.claude/skills/`) are checked by regenerating, not reading.
3. Cross-check against the design and the contracts.
4. Run the gate; copy real numbers ("pytest: 37 passed, 1 skipped").
5. Hunt cross-file inconsistency: one query filters `deleted_at` and its sibling does not, one route checks access and its sibling does not, a comment contradicts the code. Most sharp findings need the whole file.

## Report structure
1. **Header**: PR number, branch, merge base, `git diff --stat`.
2. **How this was reviewed**: 2-3 sentences, with the gate result.
3. **What this PR does**: per module, neutral; end with one question for the author.
4. **Verdict**: Approve / Approve with changes / Request changes. Name the number of blocking issues.
5. **Findings**: P0 must fix before merge (correctness, security, privacy, data). P1 must fix, may follow on the same PR. P2 worth noting (tests, duplication, names, WHAT comments).
6. **Done well**: 3-5 specific, located things worth copying.

## Finding template (every P0 and P1)
```markdown
## P<n>-<k> · <title naming the defect>
**Location:** <file>:<lines> (every relevant site)
### The problem
<mechanism, step by step>
### Why it matters
<"Fine with <test setup>; the first time <real condition>, <consequence>.">
### Suggested fix
<actual code or diff>
### Follow-up / test gap
<only if the fix needs a migration, a concurrency test, a contract bump>
```

Example (illustrative):
```markdown
## P0-1 · Two workers can claim the same job
**Location:** app/jobs/repo.py:58-71
### The problem
`claim_next_job` SELECTs the oldest queued job, then UPDATEs it in a second statement. Nothing locks the row in between.
### Why it matters
Fine with one worker in tests. With two: t0 A selects job 7, t1 B selects job 7, t2 both set it running. Both transcribe, the second result overwrites the first.
### Suggested fix
UPDATE transcription.processing_job SET status='running', attempts=attempts+1, heartbeat_at=now()
WHERE id = (SELECT id FROM transcription.processing_job WHERE status='queued'
            ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING *;
### Follow-up / test gap
Two concurrent claims against Postgres must return different ids.
```

## Signature moves
- Root cause over symptom, down to library or database semantics. Example: `scheduled_at` without `timezone=True` returns naive datetimes, so the T-1h comparison with `datetime.now(UTC)` raises `TypeError` on the first real session while the naive test fixture stays green.
- A concrete interleaving for every concurrency claim.
- Separate bug classes: one correctness bug is not the same as a naming habit. Do not inflate nits.
- Cite both sites when code contradicts a rule written elsewhere.
- Praise as specific and located as criticism.

## Project checklist
`D="git diff origin/main...HEAD"`

**1. Clinical data (P0)**
- Content in logs or errors: `$D | grep -nE '^\+.*(log(ger)?\.|print\(|console\.(log|error)).*(transcript|segments|text|content|summary|recommendation|name|date_of_birth|goal)'`. `HTTPException(detail=...)` echoing request content is a leak.
- Outbound calls: `$D | grep -nE '^\+.*(httpx|requests\.|aiohttp|fetch\(|openai|anthropic)'`. Allowed: worker to our API, worker to Ollama on the same host, API to admin-backend JWKS. A hosted LLM API is a P0.
- New files under `tests/`: open them; synthetic or public data only.
- `/ai` responses with clinical data send `Cache-Control: no-store`.

**2. Auth (P0)**
- Every route has an auth dependency except `GET /ai/health`: `grep -n "@router\." app/`.
- `jwt.decode` pins the algorithm and requires every claim documented in admin-backend `app/modules/auth_rbac/tokens.py`.
- `/ai/internal/*` accepts only the worker token (`hmac.compare_digest`), never a user JWT; user routes never accept the worker token.

**3. Access (P0)**
- Every session-scoped read (session, case note, attachment, job, audio, photos) applies the access rule in `transcription-backend/docs/DESIGN.md` Security.
- Test with two psychologists: A asks for B's session id and gets 404, not 403.

**4. Soft deletes (P1; P0 if deleted clinical data shows)**
- Every read filters `deleted_at IS NULL`, including joins and counts. Compare with sibling queries.

**5. Case-note lifecycle (P0)**
- Every rule in `DESIGN.md` Case-note lifecycle has a code path that enforces it. Look for: an edit path that skips the job check, a job setting `approved_by`, a user route setting `final`.

**6. Data layout and migrations (P0 when data can be lost)**
- Layout per `DESIGN.md` Data; neither repo migrates the other's schema.
- Read autogenerated revisions by hand (enums, defaults, `nullable` on existing rows). Run on Postgres, not SQLite: `alembic upgrade head && alembic downgrade -1 && alembic upgrade head`.
- Postgres cannot use an enum value added with `ALTER TYPE ... ADD VALUE` in the same transaction.

**7. Contracts (P1; P0 if a client breaks)**
- Route or schema change: `python -m app.export_openapi --check` passes and `openapi/openapi.yaml` is in the diff.
- Frontend: `contracts.lock.json` bumped on purpose; `contracts/` and `src/api/generated/` regenerated by `./scripts/sync-contracts.sh`, never hand-edited.
- Breaking change: plan for the old cached PWA, which keeps calling the old shape until reload.

**8. Resources (P0 on the VM, P1 on the GPU)**
- The VM has no GPU and no swap: `python -X importtime -c "import app.main" 2>&1 | grep -iE "torch|whisperx|pyannote"` prints nothing. Audio is streamed to disk, never `await file.read()`. List queries are bounded.
- Stored file paths are built from ids, never from the uploaded filename.
- transcription-backend: the Package boundaries checks in its `AGENTS.md` pass.
- The JupyterHub GPU is shared: memory released after each job; Ollama `keep_alive` bounded, `num_ctx` set.

**9. Frontend PWA (P0 for caching clinical data)**
- `runtimeCaching` stays `[]`; `navigateFallbackDenylist` keeps `/api/`, `/ai/`, `/ws`.
- No token in `localStorage` or `sessionStorage`.
- Audio plays from the authenticated `/ai/...` URL, not a blob (CSP has no `media-src blob:`).

**10. Comments and names (P2)**
- A comment restating the next line: quote it. Names carry units and say what the thing is.
