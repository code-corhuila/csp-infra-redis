#!/usr/bin/env sh
# Stops the Redis instance of an environment. The instance has no volume: its keys are lost on purpose (ADR-028).
# Usage: ./scripts/down.sh dev|qa|main
set -eu
cd "$(dirname "$0")/.."
env_name="${1:?usage: down.sh dev|qa|main}"
docker compose --env-file "env/$env_name.env" down
