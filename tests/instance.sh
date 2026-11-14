#!/usr/bin/env sh
# Checks the running instance of the current Compose project (the access rules of ADR-028). The CI runs it after
# `docker compose up -d --wait redis`; it can be run by hand with REDIS_ADMIN_PASSWORD and AUTH_REDIS_PASSWORD set.
set -u
cd "$(dirname "$0")/.."
admin_password="${REDIS_ADMIN_PASSWORD:?set REDIS_ADMIN_PASSWORD}"
auth_password="${AUTH_REDIS_PASSWORD:?set AUTH_REDIS_PASSWORD}"
failures=0

# cli <user> <password> <command...>: runs redis-cli inside the container; the password never reaches the process list
cli() {
  cli_user=$1; cli_password=$2; shift 2
  docker compose exec -T -e REDISCLI_AUTH="$cli_password" redis redis-cli --no-auth-warning --user "$cli_user" "$@" 2>&1
}
# expect <description> <expected text> <actual output>
expect() {
  case "$3" in
    *"$2"*) echo "ok   $1" ;;
    *) echo "FAIL $1: expected '$2', got '$3'"; failures=$((failures + 1)) ;;
  esac
}
auth() { cli auth_app "$auth_password" "$@"; }
admin() { cli redis_admin "$admin_password" "$@"; }
wait_healthy() { docker compose up -d --wait redis >/dev/null 2>&1; }

expect "a connection without user is refused" NOAUTH "$(docker compose exec -T redis redis-cli ping 2>&1)"
expect "the default user is off" WRONGPASS "$(cli default "$admin_password" ping)"
expect "a wrong password is refused" WRONGPASS "$(cli auth_app wrong ping)"
expect "redis_admin pings" PONG "$(admin ping)"
expect "auth_app pings" PONG "$(auth ping)"

for key in attempts:probe locked:probe blacklist:probe; do
  expect "auth_app SET $key" OK "$(auth set "$key" 1)"
  expect "auth_app GET $key" 1 "$(auth get "$key")"
  expect "auth_app EXISTS $key" 1 "$(auth exists "$key")"
  expect "auth_app INCR $key" 2 "$(auth incr "$key")"
  expect "auth_app EXPIRE $key" 1 "$(auth expire "$key" 300)"
  ttl=$(auth ttl "$key")
  if [ "$ttl" -gt 0 ] 2>/dev/null && [ "$ttl" -le 300 ]; then echo "ok   auth_app TTL $key"; else echo "FAIL auth_app TTL $key: got '$ttl'"; failures=$((failures + 1)); fi
  expect "auth_app DEL $key" 1 "$(auth del "$key")"
done

expect "auth_app cannot write another prefix" NOPERM "$(auth set other:probe 1)"
expect "auth_app cannot read another prefix" NOPERM "$(auth get other:probe)"
expect "auth_app cannot FLUSHALL" NOPERM "$(auth flushall)"
expect "auth_app cannot CONFIG" NOPERM "$(auth config get '*')"
expect "auth_app cannot KEYS" NOPERM "$(auth keys '*')"
expect "auth_app cannot PUBLISH" NOPERM "$(auth publish attempts:probe 1)"
expect "redis_admin reads the configuration" maxmemory "$(admin config get maxmemory)"

expect "the save setting exists" save "$(admin config get save)"
if [ -z "$(admin config get save | tail -n 1)" ]; then echo "ok   no save schedule: nothing is written to disk"; else echo "FAIL the save schedule is not empty"; failures=$((failures + 1)); fi
expect "the append-only file is off" no "$(admin config get appendonly | tail -n 1)"
expect "eviction takes the shortest TTL first" volatile-ttl "$(admin config get maxmemory-policy | tail -n 1)"
max_memory=$(admin config get maxmemory | tail -n 1)
[ "$max_memory" -gt 0 ] 2>/dev/null && echo "ok   maxmemory is $max_memory bytes" || { echo "FAIL maxmemory is '$max_memory'"; failures=$((failures + 1)); }

# an unpublished port is reported as ":0"; any other host port would mean the instance is open to the host
published=$(docker compose port redis 6379 2>&1)
if echo "$published" | grep -Eq ':[1-9][0-9]*$'; then echo "FAIL port 6379 is published: $published"; failures=$((failures + 1)); else echo "ok   port 6379 is not published"; fi

auth set attempts:restart 1 >/dev/null
docker compose restart redis >/dev/null 2>&1
wait_healthy
expect "a restart empties the instance" 0 "$(auth exists attempts:restart)"
expect "the users work after a restart" OK "$(auth set attempts:restart 1)"
wait_healthy && echo "ok   starting again changes nothing" || { echo "FAIL starting again"; failures=$((failures + 1)); }
docker compose up -d --wait --force-recreate redis >/dev/null 2>&1
expect "the users work after the container is recreated" PONG "$(auth ping)"

[ "$failures" -eq 0 ] && echo "all checks passed" || { echo "$failures check(s) failed"; exit 1; }
