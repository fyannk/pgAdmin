# Building, publishing and maintaining

## Local builds

Build the upstream-compatible variant from this repository:

```text
docker build --pull -f Dockerfile.upstream -t fyannk/pgadmin:9.17 .
```

The hardened Docker build context **must be the matching pgAdmin source
checkout**, not this repository. With the sibling checkout supplied for
development:

```text
git -C ../pgadmin4 checkout REL-9_17
docker build --pull -f Dockerfile -t fyannk/pgadmin:9.17-hardened ../pgadmin4
```

The `--pull` flag is important for the hardened image: it refreshes the Python,
Alpine, and PostgreSQL builder images before the final image runs `apk upgrade`
and rebuilds Python packages.

To inspect only vulnerabilities that have a published fix, use:

```text
grype fyannk/pgadmin:9.17-hardened --only-fixed
```

Run an unrestricted scan as well when policy requires it; findings without a
fixed version need a documented risk decision rather than an image-layer
cleanup. The scheduled build refreshes the selected Python and Alpine bases, so
run the scan against the tag intended for deployment rather than relying on a
previous report.

Check a local build the way CI and the publish do:

```text
.github/scripts/check-image.sh fyannk/pgadmin:9.17-hardened hardened
.github/scripts/check-image.sh fyannk/pgadmin:9.17 upstream
```

## Release automation

The scheduled workflow resolves the latest stable `dpage/pgadmin4` version and
handles both variants the same way: build the image, run
[`check-image.sh`](../.github/scripts/check-image.sh) against it — the same checks
CI runs on a pull request — and only then push it, by digest and untagged, with
SBOM and provenance attestations. The push reuses the checked build's layers,
and the workflow fails if the pushed image differs from the checked one. The
verified digest is then signed with cosign, and only after that do the tags
move to it, so no tag ever serves an unchecked or unsigned image.

The upstream-compatible `<version>` is built only if that tag does not exist
yet, and never rebuilt afterwards. The hardened image is built from the exact
`pgadmin-org/pgadmin4` `REL-x_y` source tag and tagged `<version>-hardened`,
plus `latest` when it is the newest stable release.

The hardened image is rebuilt only when an input that can change its contents
has moved: the pgAdmin source revision, the `Dockerfile`, or the digest of any
base image it builds from (read from the recipe itself, so a base bump there is
followed). That fingerprint is recorded on the image as the
`io.fyannk.pgadmin.inputs` label and compared against the published
`<version>-hardened`. A rebuild happens regardless once the published image is
more than seven days old, so a dependency patch with unchanged base images is
still picked up. A manual run can pick an older release or force a rebuild;
an older release never moves `latest`.

GHCR is where images are built, checked and tagged. Docker Hub is a mirror:
once the publish jobs are done, a single job copies to Docker Hub every tag
whose digest differs there, attestations included
([`sync-dockerhub.sh`](../.github/scripts/sync-dockerhub.sh)), so a tag resolves to
the same digest on both. A Docker Hub account gets 200 registry requests an
hour, so the mirror reads Hub's current tags from the Hub API, skips unchanged
tags and retries a throttled copy; anything it misses is copied by the next
run. Base images are pulled through Google's Docker Hub mirror,
`mirror.gcr.io`, which serves the same digests without counting against those
limits. Docker Hub is used only when the `DOCKERHUB_USERNAME` and
`DOCKERHUB_TOKEN` secrets are set (a personal access token with read, write and
delete access).

An image replaced by a newer push stays in both registries, untagged and
pullable by digest, for seven days. After that the cleanup that runs after each
publish deletes it: on GHCR through
[ghcr-cleanup-action](https://github.com/dataaxiom/ghcr-cleanup-action),
together with signatures left without an image, on Docker Hub through
[`prune-dockerhub.sh`](../.github/scripts/prune-dockerhub.sh). Tagged images are
never deleted, and no daily date tags are created. Docker Hub's manifest API is
not part of Docker's published reference, so a failed Hub cleanup is reported
as a warning rather than failing the publish.

Published images, for `linux/amd64`:

- `ghcr.io/fyannk/pgadmin:<version>`, `fyannk/pgadmin:<version>`
- `ghcr.io/fyannk/pgadmin:<version>-hardened`, `fyannk/pgadmin:<version>-hardened`
- `ghcr.io/fyannk/pgadmin:latest`, `fyannk/pgadmin:latest` (hardened)

## Merge automation

The ruleset on `main` requires the four jobs
[`ci.yml`](../.github/workflows/ci.yml) runs on a pull request — lint, build,
container profiles, and the vulnerability scan — plus the CodeQL analysis of
the workflows, and requires that review threads be resolved. It requires no
approvals: the gate is the pipeline and the reading, not a rubber stamp.
Copilot is requested on every pull request automatically; its review is always
a comment, never an approval, so it cannot approve a change, but an unresolved
thread it opens does hold the merge until someone answers it.

Branches need not be up to date with `main` to merge. Requiring that would
catch the case where two pull requests pass alone and break together, but
nothing rebases a stale branch on its own: auto-merge only waits and merges,
and Dependabot refreshes a branch when its manifest conflicts, not when `main`
moves. The requirement would trade a rare class of conflict for a queue that
stalls on every merge. `ci.yml` runs on pushes to `main` as well, so a
conflict that slips through surfaces there within minutes.

Dependabot's patch and minor bumps, grouped weekly by
[`dependabot.yml`](../.github/dependabot.yml), queue themselves through
[`automerge.yml`](../.github/workflows/automerge.yml) and land the moment the
required checks go green. Anything else, a major among them, is left for a
person: the workflow arms auto-merge from an allowlist, so an update type it
has not seen stops rather than merges.

What Dependabot watches is the hardened recipe's bases — Alpine, Python, and
the PostgreSQL client builders — plus the actions every workflow pins. The
upstream-compatible image is deliberately outside that: it mirrors an official
pgAdmin release, and which release it tracks is resolved by the publish
workflow rather than bumped in a pull request. The `dpage/pgadmin4` base is
ignored for that reason.
