# How the images are checked and measured

## Before an image ships

Every pull request builds both variants against the pgAdmin release the next
publish would ship, and runs
[`check-image.sh`](../.github/scripts/check-image.sh) against each result.
The publish runs the same script on the image it is about to push, and moves
no tag if it fails.

Both variants:

- run unprivileged by default;
- carry no capability-bearing `python3-cap` interpreter;
- start under an arbitrary UID in GID `0`, as OpenShift assigns one.

The hardened variant also:

- has no `postfix`, `sudo`, `libcap` or `libcap-utils` package, and no
  postfix startup block in its entrypoint;
- has no setuid or setgid file anywhere in the exported filesystem;
- keeps `pip` and `wheel` out of the runtime virtual environment;
- ships the PostgreSQL 14–18 client utilities pgAdmin calls.

The hardened image is also scanned with grype. The gate blocks on critical
findings with an applicable fix that the change introduces; one already in the
published image is tracked by a nightly-updated issue, and every other finding
with a fix is published to the repository's code scanning results. See
[SECURITY.md](../SECURITY.md).

## The nightly security report

[fyannk.github.io/pgAdmin](https://fyannk.github.io/pgAdmin/) compares both
variants of the newest pgAdmin release with the official `dpage/pgadmin4`
image each night, using two scanners. Every side is inventoried with Syft:
ours from the SBOM attached when it is published, the official image by
running Syft on it. grype scans those SBOMs and Trivy scans the images. For
each variant, side and scanner, the page shows every severity as "with a fix /
all findings", with the trend over time and the digest each tag points to. The
page also records when each scanner's advisory database was built, and flags
one built more than two days before the scan, since a clean result is only as
current as that database. The data and our SBOMs are published alongside the
page.

[`security-report.yml`](../.github/workflows/security-report.yml) runs after
the nightly publish and on changes to [`site/`](../site) or
[`security-report.sh`](../.github/scripts/security-report.sh). The official
image and the Trivy image are pulled through `mirror.gcr.io`, Google's mirror
of Docker Hub, which serves the same digests without touching Docker Hub's
rate limits.
