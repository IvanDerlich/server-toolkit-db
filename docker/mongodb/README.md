# MongoDB (Docker)

This folder provides a local MongoDB container, required environment configuration, and startup helpers.

## File Responsibilities

- `docker-compose.yml`: runtime wiring. Builds the hardened image, mounts data/TLS assets, sets non-root user, and defines healthcheck.
- `Dockerfile`: image assembly. Copies hardened configs and entrypoint, then drops to non-root runtime user.
- `image/mongod.conf`: steady-state MongoDB runtime config (auth on, TLS required).
- `image/mongod-init.conf`: temporary first-run bootstrap config (local-only, no TLS/auth) used only to seed users.
- `image/entrypoint.sh`: first-run bootstrap logic. Creates root/app users on empty data volume, then starts hardened `mongod`.
- `start-or-restart.sh`: operator wrapper that delegates to `scripts/start.sh`.
- `.env`: local runtime values used by scripts and compose.
- `.env.example`: template and defaults for required env values.
- `.generated/tls/*`: generated local CA and server certificate files (created by `scripts/start.sh`).
- `scripts/start.sh`: orchestration script. Validates env, generates TLS assets, prepares volume ownership, recreates container.
- `scripts/env-file-load-and-validate.sh`: shared env loading and validation helpers for all scripts.
- `scripts/sanity-check.sh`: preflight checker (env + port + openssl) without starting containers.
- `scripts/print-setup-guide.sh`: prints connection, logs, and verification commands after startup.
- `scripts/cleanup.sh`: manual teardown/reset utility for this stack (supports safe cleanup and full reset modes).
## All security and connection checks are now part of scripts/integration-test.sh.
- `scripts/integration-test.sh`: post-deploy smoke tests — verifies app user collection CRUD and root user lifecycle end-to-end. Can be re-run at any time against a running instance (see *Running integration tests* section).

## Why Two MongoDB Config Files

- `image/mongod-init.conf` is for first-run bootstrap only.
- It starts a local-only temporary mongod (`bindIp: 127.0.0.1`) so the entrypoint can create root/app users before hardened runtime starts.
- `image/mongod.conf` is the steady-state runtime config used after bootstrap (and on all later restarts).
- It enforces the hardening controls: authentication enabled and TLS required.

## Execution Timeline (File By File)

1. `start-or-restart.sh` runs when an operator starts/recreates the service.
Reason: keep a single public command that always delegates to one canonical startup flow.
2. `scripts/start.sh` runs next.
Reason: validate env, ensure non-root runtime IDs, generate/reuse TLS assets, and fix data-volume ownership.
3. `scripts/env-file-load-and-validate.sh` is sourced by `scripts/start.sh` and other operational scripts.
Reason: centralize env loading/validation logic to avoid drift.
4. `docker-compose.yml` is evaluated by `docker compose up`.
Reason: define runtime wiring (image/build, user, security options, mounts, healthcheck).
5. `Dockerfile` is used at build time (or reused if already built).
Reason: assemble a hardened image with configs and custom entrypoint, then drop privileges.
6. `image/entrypoint.sh` runs inside the container at startup.
Reason: perform idempotent first-run bootstrap logic that depends on actual container state (`/data/db` empty or not).
7. `image/mongod-init.conf` is used only during first-run bootstrap branch in entrypoint.
Reason: temporary local bootstrap process for user creation before hardening is enforced.
8. `image/mongod.conf` is used by final mongod process (`CMD`).
Reason: enforce steady-state hardened runtime settings.
9. `scripts/print-setup-guide.sh` runs after container readiness check.
Reason: print deterministic operator commands for TLS connections and verification.
10. `scripts/cleanup.sh` is manual-only and runs only when an operator explicitly invokes it for teardown/reset.
Reason: provide a controlled cleanup path (preserve data or full reset) before re-running startup.

## Start or recreate MongoDB

1. Copy `.env.example` to `.env` and set real values.
2. Optional validation:

```bash
sudo bash ./scripts/sanity-check.sh
```

3. Start or recreate the instance:

```bash
sudo bash ./start-or-restart.sh
```

The script is the source of truth for the operational flow and does not call `scripts/cleanup.sh`.

## Important behavior

- The service binds to `127.0.0.1` only.
- The container runs as non-root by default (`MONGODB_UID:MONGODB_GID`, default `999:999`).
- Linux capabilities are dropped and `no-new-privileges` is enabled.
- Authentication is enabled (`security.authorization: enabled`).
- TLS is required for client connections.
- The root user and application user are created only on first initialization of an empty data volume.
- If you change database usernames or passwords later, remove the existing volume with `scripts/cleanup.sh` and start again.

## Least-privilege verification

```bash
sudo docker inspect app-mongodb --format 'user={{.Config.User}} cap_drop={{.HostConfig.CapDrop}} security_opt={{.HostConfig.SecurityOpt}}'
```

## Cleanup

`scripts/cleanup.sh` is a manual utility for safely stopping/removing the stack.
It supports both non-destructive cleanup (preserve data) and full reset (delete data).

Use script help as the source of truth for current options:

```bash
sudo bash ./scripts/cleanup.sh --help
```

## Before public exposure

Run security preflight checks first:

```bash
## (No longer needed: all checks are in integration-test.sh)
```

This script prints each operation as it runs and verifies:
- TLS-only enforcement (`requireTLS`)
- unauthenticated access is denied
- app user can access app DB but is blocked from admin-only commands
- placeholder credential detection

Current default posture is TLS + username/password auth (not mTLS), because client certificates are not mandatory when `allowConnectionsWithoutCertificates: true`.
For stronger internet-facing posture, require client certificates (mTLS) and rotate strong credentials.

## Running integration tests

The integration test script verifies that the app user and root user can perform their expected operations end-to-end (collection CRUD and user lifecycle). It can be run at any time against a running instance — all test data uses the `_smoketest_` prefix and is cleaned up both before and after each run.

Requires the container to be running:

```bash
sudo bash ./scripts/integration-test.sh
```

Typical usage after deployment:

```bash
sudo bash ./start-or-restart.sh
sudo bash ./scripts/integration-test.sh
```

## Future Improvements

Automated backups with retention and offsite copy.
Automated restore verification (spin up temp instance, restore, run smoke tests).
Secret management upgrade (remove plain passwords from env files).
TLS lifecycle automation (expiry checks, rotate certs before they age out).
CI checks on every push (lint scripts, run integration test, run security preflight).
One-command new-instance generator (name, port, domain, creds, done).
Built-in observability pack (metrics, dashboard, alerts for health/disk/latency).
Upgrade runway script (test MongoDB version upgrades safely before production).
Optional replica-set profile for high availability.
Short operations playbook for incidents (backup restore, cert rotation, rollback).