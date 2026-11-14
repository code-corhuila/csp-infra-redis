# Changelog

All notable changes of `csp-infra-redis` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Each change is recorded in the pull request that introduces it.

## [Unreleased]

## [3.0.0] - 2026-10-15

### Added

- The single Redis instance of the platform for the auth state (ADR-028): `compose.yml` with the pinned image
  `redis:7.4.11-alpine`, no persistence, `maxmemory` with `volatile-ttl`, no published port and the `platform` network;
  the ACL template `redis/users.acl.template` (`default` off, `redis_admin`, `auth_app` limited to `attempts:*`, `locked:*`
  and `blacklist:*`); the env examples of `dev`, `qa` and `main`; `scripts/up.sh` and `scripts/down.sh`.
- `.github/workflows/ci.yml` and `tests/instance.sh`: they start the instance and check the users, the permissions, the
  persistence settings, the unpublished port and the restart.
- The pull request template of the annex, `.gitignore` and `.gitattributes`.
- This changelog.

### Changed

- `README.md` describes the instance, its variables, its users and the accepted restart risk, and cites ADR-028.
