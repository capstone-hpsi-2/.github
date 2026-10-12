# User Guide — Run locally and test

The stack's master gate is **`admin-backend/deploy/smoke-test.sh`**. It boots the whole system,
runs every cross-repo assertion, and with `--keep` leaves it running so you can use the app.
This guide just shows you how to drive that workflow.

## 1. Prerequisites

- Docker Engine >= 24 with Compose v2 — check: `docker compose version`
- All repos checked out **side by side**:
  `frontend/` · `admin-backend/` · `transcription-backend/` · `.github/`
- Free ports 8443 (HTTPS) and 8080 (HTTP redirect)

## 2. Run the smoke test (builds, boots, verifies)

```bash
cd admin-backend/deploy
./smoke-test.sh --local --keep
```

Notes:

- `--local` builds all three repos from the sibling checkouts. Omit it only once images are
  published to the registry (`IMAGE_REGISTRY` in `.env`), in which case it pulls `nginx` and
  `transcription` instead.
- `--keep` leaves the stack running after the checks pass. Without it, the stack is torn down
  when the script exits.
- First run: copies `.env.example` → `.env` and generates the JWT signing key in `secrets/`.
- `PASS` across every assertion = "backbone done". On failure it prints the compose logs.

## 3. Use the app

```bash
open https://localhost:8443        # self-signed cert: accept once
```

Log in with the seeded dev user (from `deploy/.env`):

| Field | Value |
|---|---|
| Email | `admin@example.com` |
| Password | `change-me-dev-only` |
| 2FA (TOTP) | secret `JBSWY3DPEHPK3PXP` in any authenticator app |

## 4. Spot-check by hand

```bash
BASE=https://localhost:8443
curl -sk $BASE/api/health          # {"status":"ok","service":"admin-backend","version":"..."}
curl -sk $BASE/ai/health           # {"status":"ok","service":"transcription-backend","version":"..."}
curl -sk $BASE/api/.well-known/jwks.json   # public RS256 keys
```

## 5. Tear down / reset

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml down -v
```

## Where the details live

| Topic | Home |
|---|---|
| Smoke test flags, what it asserts, tunnel (phase 2), LAN/phone testing | `admin-backend/deploy/README.md` |
| Contribute / branch / PR / security rules | `.github/CONTRIBUTING.md` |
| Per-repo layout, dev loops, contracts | each repo's `README.md` |

Docs policy across the org: `.github/docs/` is the home for anything that applies to more than one
repo. **One home per fact** — every other mention is a link, never a restated copy.