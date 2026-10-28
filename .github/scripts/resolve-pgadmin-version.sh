#!/usr/bin/env bash
# Print the pgAdmin release the images are built from: the given version when
# one is passed, otherwise the newest stable dpage/pgadmin4 tag. The publish
# workflow and CI both call this, so CI always tests the release the next
# scheduled publish would ship.
set -euo pipefail

version="${1:-}"
if [[ -z "${version}" ]]; then
  version="$(
    curl -fsSL "https://registry.hub.docker.com/v2/repositories/dpage/pgadmin4/tags?page_size=100" \
      | jq -r '.results[].name' \
      | grep -E '^[0-9]+\.[0-9]+$' \
      | sort -V \
      | tail -n 1
  )"
fi

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "Could not determine a pgAdmin version (got '${version}')" >&2
  exit 1
fi

echo "${version}"
