# csp-infra-redis

> The single Redis instance of the platform: the state of auth that must expire by itself (ADR-028)

Part of the **Cinesync Platform** distributed system — team `cinesync-platform`, Group 1.
Governance and documentation live in [`csp-docs`](https://github.com/code-corhuila/csp-docs).
The decision is recorded in ADR-028 (`ADR-028-redis-instance-for-the-auth-state`, in `05-architecture/decisions/` of `csp-docs`).

## Purpose

`csp-auth-api` keeps three kinds of short-lived state in Redis: the counters of failed login attempts, the temporary
locks of an account and the revoked `jti` (the blacklist). Each key expires by TTL. This repository **defines the only
Redis instance** of each environment; it holds no application data and no schema.

```
compose.yml                    the redis service: pinned image, ACL file, no persistence, memory limit, health check
redis/users.acl.template       the users and their permissions, without any secret
env/<env>.env.example          one file per environment: dev, qa, main (git-ignored without .example)
scripts/up.sh · down.sh        bring an environment up (waits until healthy) and stop it
tests/instance.sh              the checks of the CI, also runnable by hand
.github/workflows/ci.yml       starts the instance and runs the checks
```

## Environments and variables

Each environment has its own env file and its own `COMPOSE_PROJECT_NAME` (`csp-dev`, `csp-qa`, `csp-main`), and
therefore its own container (J.5.1). Only the `.example` file is versioned. In `qa` and `main` the real values come
from the secret of the environment, never from the repository.

| Variable | Meaning |
|---|---|
| `COMPOSE_PROJECT_NAME` | Compose project of the environment |
| `REDIS_ADMIN_PASSWORD` | password of `redis_admin` |
| `AUTH_REDIS_PASSWORD` | password of `auth_app`; it goes inside a URL, so use a URL-safe value: `openssl rand -hex 24` |
| `REDIS_MAXMEMORY` | upper bound of the memory (default `64mb`) |
| `APP_AUTH_REDIS_URL` | what `csp-auth-api` reads: `redis://auth_app:${AUTH_REDIS_PASSWORD}@redis:6379/0` |

## How to run

```bash
cp env/dev.env.example env/dev.env      # then set both passwords
./scripts/up.sh dev                     # creates the platform network, starts Redis and waits until it is healthy
./scripts/down.sh dev                   # stops it
./scripts/up.sh qa                      # the environment argument is mandatory
```

The image is `redis:7.4.11-alpine`, pinned by version. The port is not published to the host: services reach Redis by
the name `redis` on the `platform` network, never by `localhost`.

## Users

`compose.yml` builds the ACL file at every start from the template and the passwords of the environment, and keeps it
inside the container with mode `400`. Only the SHA-256 of each password is written to it. The file is never versioned.

| User | State | Permissions | Used by |
|---|---|---|---|
| `default` | off | none: nobody connects without a named user | no one |
| `redis_admin` | on | every key and command | operation and the container health check |
| `auth_app` | on | keys `attempts:*`, `locked:*`, `blacklist:*`; commands `get`, `set`, `exists`, `incr`, `expire`, `ttl`, `del`, `ping` | `csp-auth-api` |

A service never connects as `redis_admin`.

## Health and operation

The health check of the container sends a `PING` authenticated as `redis_admin`. To look at the instance by hand:

```bash
docker compose --env-file env/dev.env exec -e REDISCLI_AUTH="<REDIS_ADMIN_PASSWORD>" redis redis-cli --user redis_admin ping
docker compose --env-file env/dev.env exec -e REDISCLI_AUTH="<REDIS_ADMIN_PASSWORD>" redis redis-cli --user redis_admin info memory
```

## Rules

- **No persistence.** `save ""` and `appendonly no`: nothing is written to disk and the instance has no volume. The
  image declares `/data` as a volume, so it is mounted as `tmpfs` to stop Docker from creating an anonymous one.
- **Explicit limits (5.3.10).** `maxmemory` is set and `maxmemory-policy` is `volatile-ttl`: when the limit is
  reached, the keys closest to expire go first.
- **No secret is versioned.** `env/*.env.example` carries names and placeholders only.
- **No port is published.** Only the gateway is reachable from the host.
- **Accepted risk: a restart empties the instance.** The attempt counters and the temporary locks are lost, so an
  account locked by `auth` is released and the count of failed attempts starts again. ADR-028 accepts this risk and
  lists its mitigations; the administrative lock (`status = LOCKED` in the auth database) is not stored in Redis and
  survives a restart.

## Tests

`tests/instance.sh` is the check that the CI runs after starting the instance. It verifies that `default` is rejected,
that `auth_app` can run its commands on its three prefixes and gets `NOPERM` on other keys, `FLUSHALL`, `CONFIG` and
`KEYS`, that `redis_admin` works, that `save` is empty and `appendonly` is `no`, that the port is not published to the
host, that a restart clears the keys and that starting again does not fail. To run it by hand against a running
instance, set `COMPOSE_PROJECT_NAME`, `REDIS_ADMIN_PASSWORD` and `AUTH_REDIS_PASSWORD` and run `sh tests/instance.sh`.

## Branching

Three permanent branches. **None of them accepts a direct commit** â€” you enter through a child
branch and leave through a Pull Request.

```
develop  <--PR--  feat/... fix/... chore/...
qa       <--PR--  qa/...
main     <--PR--  release/...  hotfix/...
```

Promotion happens **by re-application** (`git cherry-pick -x`), never by merging one permanent
branch into another: `merge develop -> qa` and `merge qa -> main` do not exist in this model.

`main` requires **1 approval from `ariel5253`**. On `develop` and `qa` the team sets its own review
rule.

Full policy: `00-governance/branching-policy.md` in `csp-docs`.
