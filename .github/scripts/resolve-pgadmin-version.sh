#!/usr/bin/env bash
# Print the pgAdmin release the images are built from: the given version when
# one is passed, otherwise the newest stable release that has both an official
# dpage/pgadmin4 image and a REL-x_y source tag in pgadmin-org/pgadmin4. The
# publish workflow, CI and the security report all call this, so CI always
# tests the release the next scheduled publish would ship.
#
# Both are required because both variants need them: the upstream-compatible
# image is built FROM the official image, the hardened one from the source
# tag. The two do not always appear together (9.19's image was pushed days
# before any REL-9_19 tag), and picking a release with only one of them would
# fail every build until the other caught up.
set -euo pipefail

version="${1:-}"
if [[ -n "${version}" ]]; then
  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "Not a pgAdmin release: '${version}'" >&2
    exit 1
  fi
  echo "${version}"
  exit 0
fi

# Each listing is taken on its own so a failed request stops the script
# instead of leaving an empty list.
images="$(
  curl -fsSL "https://registry.hub.docker.com/v2/repositories/dpage/pgadmin4/tags?page_size=100" \
    | jq -r '.results[].name' \
    | grep -E '^[0-9]+\.[0-9]+$'
)"
sources="$(
  git ls-remote --tags --refs https://github.com/pgadmin-org/pgadmin4.git 'REL-*' \
    | sed -n 's#.*refs/tags/REL-\([0-9]*\)_\([0-9]*\)$#\1.\2#p'
)"

newest_image="$(sort -V <<<"${images}" | tail -n 1)"
version="$(comm -12 <(sort <<<"${images}") <(sort <<<"${sources}") | sort -V | tail -n 1)"

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "Could not determine a pgAdmin version (got '${version}')" >&2
  exit 1
fi
if [[ "${version}" != "${newest_image}" ]]; then
  echo "::warning::dpage/pgadmin4:${newest_image} has no REL-${newest_image/./_} source tag yet; building ${version}" >&2
fi

echo "${version}"
