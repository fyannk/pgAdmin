#!/usr/bin/env bash
# Assert the properties an image exists for, against the image as built:
#
#   .github/scripts/check-image.sh <image> hardened|upstream
#
# CI and the publish both run this, so an image is checked by the same code
# before a pull request merges and before a tag is moved to it.
set -euo pipefail

image="${1:?usage: $0 <image> hardened|upstream}"
variant="${2:?usage: $0 <image> hardened|upstream}"
case "${variant}" in
  hardened | upstream) ;;
  *) echo "unknown variant: ${variant}" >&2; exit 2 ;;
esac
fail=0
smoke="pgadmin-smoke-$$"
network="pgadmin-smoke-$$"
# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap
cleanup() {
  docker rm -f "${smoke}" >/dev/null 2>&1 || true
  docker network rm "${network}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "::group::Runs unprivileged by default"
user="$(docker image inspect "${image}" --format '{{.Config.User}}')"
echo "Config.User=${user}"
# The upstream image names its user; the hardened one pins the UID.
if [[ "${variant}" == "hardened" && "${user}" != "5050" ]] ||
   [[ "${variant}" == "upstream" && "${user}" != "pgadmin" && "${user}" != "5050" ]]; then
  echo "FAIL: unexpected default user ${user}"
  fail=1
fi
echo "::endgroup::"

echo "::group::No capability-bearing interpreter"
# The python3-cap copy carries CAP_NET_BIND_SERVICE; removing it is the one
# change both variants share.
if docker run --rm --entrypoint sh "${image}" \
     -c 'test -e /usr/local/bin/python3-cap -o -e /venv/bin/python3-cap'; then
  echo "FAIL: a python3-cap binary is present"
  fail=1
fi
echo "::endgroup::"

echo "::group::Arbitrary UID can start the application"
# OpenShift assigns an unpredictable UID in the root group, which works only
# while /etc/passwd stays group-writable.
if ! docker run --rm --user 12345:0 --entrypoint sh "${image}" -c '
  set -e
  test -w /etc/passwd
  test -w /var/lib/pgadmin
  /venv/bin/python3 -c "import psycopg, flask, gunicorn; print(\"imports ok\")"
'; then
  echo "FAIL: an arbitrary UID in GID 0 cannot start the application"
  fail=1
fi
echo "::endgroup::"

if [[ "${variant}" == "upstream" ]]; then
  exit "${fail}"
fi

echo "::group::Privileged components are absent"
installed="$(docker run --rm --entrypoint apk "${image}" info)"
for pkg in postfix sudo libcap libcap-utils; do
  if grep -qx "${pkg}" <<<"${installed}"; then
    echo "FAIL: ${pkg} is installed"
    fail=1
  fi
done

if docker run --rm --entrypoint grep "${image}" -q 'Start Postfix' /entrypoint.sh; then
  echo "FAIL: the postfix startup block survived"
  fail=1
fi

if ! docker run --rm --user 12345:0 --entrypoint test "${image}" -w /run/pgadmin; then
  echo "FAIL: /run/pgadmin is not writable by an arbitrary UID in GID 0"
  fail=1
fi

# Read the exported filesystem rather than searching from inside a container,
# so every directory is visible without running as root.
cid="$(docker create "${image}")"
setuid="$(docker export "${cid}" | tar -tvf - | awk '$1 ~ /^-(..[sS]|.....[sS])/')"
docker rm "${cid}" >/dev/null
if [[ -n "${setuid}" ]]; then
  echo "FAIL: setuid/setgid binaries are present:"
  echo "${setuid}"
  fail=1
fi
echo "::endgroup::"

echo "::group::Build-time Python tooling stays out of the runtime venv"
for pkg in pip wheel; do
  if docker run --rm --entrypoint sh "${image}" \
       -c "ls -d /venv/lib/python3*/site-packages/${pkg}-*.dist-info" >/dev/null 2>&1; then
    echo "FAIL: ${pkg} is installed in /venv"
    fail=1
  fi
done
# setuptools is a genuine runtime dependency from requirements.txt.
if ! docker run --rm --entrypoint sh "${image}" \
     -c 'ls -d /venv/lib/python3*/site-packages/setuptools-*.dist-info' >/dev/null; then
  echo "FAIL: setuptools, a runtime dependency, is missing from /venv"
  fail=1
fi
echo "::endgroup::"

# Executing each binary catches a missing shared library or a wrong
# architecture, which a mode-bit test cannot.
echo "::group::PostgreSQL client utilities run"
if ! docker run --rm --entrypoint sh "${image}" -c '
  set -e
  for major in 14 15 16 17 18; do
    for tool in pg_dump pg_dumpall pg_restore psql; do
      out="$("/usr/local/pgsql-${major}/${tool}" --version)"
      echo "${out}"
      case "${out}" in
        *" ${major}."*) ;;
        *) echo "${tool} for ${major} reports: ${out}" >&2; exit 1 ;;
      esac
    done
  done
'; then
  echo "FAIL: a PostgreSQL client utility is missing or does not run"
  fail=1
fi
echo "::endgroup::"

# Behind a path-prefixing proxy with proxy-supplied identity, on a read-only
# root filesystem: the most restricted way the image is run. The probe goes
# through a user network from a second container, as a proxy would reach it,
# rather than through a published host port.
echo "::group::Boots read-only and serves /misc/ping under SCRIPT_NAME"
docker network create "${network}" >/dev/null
docker run -d --name "${smoke}" --network "${network}" --read-only \
  --tmpfs /tmp \
  --tmpfs /var/lib/pgadmin:uid=5050,gid=0,mode=0770 \
  --tmpfs /run/pgadmin:uid=5050,gid=0,mode=0770 \
  --tmpfs /var/log/pgadmin:uid=5050,gid=0,mode=0770 \
  -e SCRIPT_NAME=/pgadmin \
  -e PGADMIN_LISTEN_PORT=8080 \
  -e PGADMIN_DEFAULT_EMAIL=smoke@example.com \
  -e PGADMIN_DEFAULT_PASSWORD=smoke-test-only \
  -e PGADMIN_CONFIG_AUTHENTICATION_SOURCES="['webserver']" \
  -e PGADMIN_CONFIG_WEBSERVER_REMOTE_USER="'X-Forwarded-User'" \
  -e PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False \
  "${image}" >/dev/null
booted=false
for attempt in $(seq 1 60); do
  if body="$(docker run --rm --network "${network}" --entrypoint wget "${image}" \
       -qO- "http://${smoke}:8080/pgadmin/misc/ping" 2>/dev/null)" && grep -q PING <<<"${body}"; then
    echo "ping answered after ${attempt} attempt(s): ${body}"
    booted=true
    break
  fi
  if [[ "$(docker inspect -f '{{.State.Running}}' "${smoke}")" != "true" ]]; then
    echo "the container exited before answering"
    break
  fi
  sleep 2
done
if [[ "${booted}" != "true" ]]; then
  docker logs "${smoke}" 2>&1 | tail -n 50 || true
  echo "FAIL: /pgadmin/misc/ping did not answer"
  fail=1
fi
cleanup
echo "::endgroup::"

exit "${fail}"
