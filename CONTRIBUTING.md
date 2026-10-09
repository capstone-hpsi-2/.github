# Contributing

Applies to every repo in the org: `frontend`, `admin-backend`, `transcription-backend`.

## Branches & PRs

- Branch names, the PR flow and PR titles: the Guardrails in
  [agents/AGENTS.shared.md](agents/AGENTS.shared.md) and the skill
  [create-pr](agents/skills/create-pr/SKILL.md).
- Small PRs. Squash-merge. The PR title becomes the commit message.
- CI must be green. `CODEOWNERS` decides reviewers; in `frontend`, each team reviews its own
  `src/features/*`, and both teams review `nginx/` and `contracts/`.

## The contracts (executable, not prose)

| Promise | Enforced by |
|---|---|
| Health shape `{status, service, version}` | `contract-health.yml` (this repo), called by each backend's CI |
| OpenAPI spec matches backend code | `python -m app.export_openapi --check` in each backend's CI |
| Frontend compiles against pinned specs | `npm run contracts:check && npm run typecheck` in frontend CI |
| Routing, shared JWT, 2FA, RBAC, wss, exposure | `admin-backend/deploy/smoke-test.sh` (the master gate) |
| Env names | `admin-backend/deploy/.env.example` is canonical |

### Changing an API

1. Backend PR: change code, regenerate `openapi/openapi.yaml`, commit both. Prefer **additive**
   changes: new optional fields, new endpoints.
2. Frontend PR: bump the ref in `contracts.lock.json`, run `./scripts/sync-contracts.sh`, fix type
   errors, commit.
3. Breaking change? Open a **Cross-repo contract change** issue first and agree on the rollout order.

### Security rules

- Every route is RBAC-guarded on the server. The frontend's role checks are cosmetic.
- 2FA is mandatory. Tokens without `"otp"` in `amr` are rejected by every backend.
- Never cache API responses in the service worker. Never log tokens or personal data.
- Only nginx is publicly reachable. Do not publish ports for any other container.

## Local full stack

Check out all three repos side by side, then:

```bash
admin-backend/deploy/smoke-test.sh --local --keep
```
