#!/usr/bin/env bash
# Print every external image a Dockerfile builds FROM, one per line, with the
# defaults of its global ARGs substituted:
#
#   .github/scripts/base-images.sh <Dockerfile>
#
# The publish fingerprints the hardened image on these digests. Reading them
# from the recipe, rather than listing them in the workflow, means a base bump
# Dependabot makes in the Dockerfile is the base the fingerprint follows.
set -euo pipefail

dockerfile="${1:?usage: $0 <Dockerfile>}"

awk '
  # Global ARG defaults: the ones declared before the first FROM.
  !seen_from && toupper($1) == "ARG" && index($2, "=") {
    split($2, kv, "=")
    args[kv[1]] = kv[2]
  }
  toupper($1) == "FROM" {
    seen_from = 1
    ref = ""
    # Skip flags such as --platform=.
    for (i = 2; i <= NF; i++) if ($i !~ /^--/) { ref = $i; break }
    for (name in args) {
      gsub("\\$\\{" name "\\}", args[name], ref)
    }
    for (j = i + 1; j <= NF; j++) if (toupper($j) == "AS") stages[tolower($(j + 1))] = 1
    if (!(tolower(ref) in stages) && ref != "scratch") print ref
  }
' "${dockerfile}" | sort -u | {
  # An unresolved variable would fingerprint nothing; stop instead.
  refs="$(cat)"
  if [[ -z "${refs}" ]] || grep -q '\$' <<<"${refs}"; then
    echo "could not resolve the base images of ${dockerfile}:" >&2
    echo "${refs}" >&2
    exit 1
  fi
  echo "${refs}"
}
