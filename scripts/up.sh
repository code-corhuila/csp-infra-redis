#!/usr/bin/env sh
# Creates the shared network (idempotent) and brings the Redis instance of an environment up, waiting until it is
# healthy. Usage: ./scripts/up.sh dev|qa|main
set -eu
cd "$(dirname "$0")/.."
env_name="${1:?usage: up.sh dev|qa|main}"
env_file="env/$env_name.env"
[ -f "$env_file" ] || { echo "missing $env_file: cp env/$env_name.env.example $env_file and fill it in"; exit 1; }
for name in REDIS_ADMIN_PASSWORD AUTH_REDIS_PASSWORD; do
  grep -q "^$name=." "$env_file" || { echo "$name is empty in $env_file: openssl rand -hex 24"; exit 1; }
done
docker network inspect platform >/dev/null 2>&1 || docker network create platform
docker compose --env-file "$env_file" up -d --wait redis
docker compose --env-file "$env_file" ps
