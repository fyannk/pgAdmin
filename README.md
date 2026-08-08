# pgadmin

![Variants](https://img.shields.io/badge/variants-upstream%20%2B%20hardened-1f6feb?style=for-the-badge)
![OpenShift friendly](https://img.shields.io/badge/OpenShift-restricted--friendly-ee0000?style=for-the-badge)
![Source rebuilt](https://img.shields.io/badge/pgAdmin-source%20rebuilt-0a7f5a?style=for-the-badge)

> Two OpenShift-friendly pgAdmin variants: upstream-compatible and hardened.

## Image tags

| Tag | Variant | Use when |
| --- | --- | --- |
| `<version>` | Upstream-compatible no-cap | Immutable release image. It is published once when the matching official `dpage/pgadmin4` release first appears, with only its privileged Python capability removed. |
| `<version>-hardened` | Source-rebuilt hardened image | Mutable rebuild of that pgAdmin release with refreshed OS and Python dependencies. |
| `latest` | Source-rebuilt hardened image | Mutable rebuild of the newest supported pgAdmin release. This tag always points to the hardened variant. |

Both variants remove privileged-port support and therefore default to port
`8080` or `8443` when `PGADMIN_LISTEN_PORT` is not set. Expose them through a
Service or Route rather than restoring a file capability.

## What is different

| Area | `<version>` upstream-compatible | `<version>-hardened` |
| --- | --- | --- |
| Application | Official prebuilt `dpage/pgadmin4:<version>` | Exact `REL-x_y` pgAdmin source release rebuilt in CI |
| Image delta | Removes only the dedicated `python3-cap` binary that grants `CAP_NET_BIND_SERVICE` | Replaces the base image, rebuilds the application, and removes privileged components |
| OS packages | Retains the upstream package snapshot | Fresh base images (`--pull`) plus `apk upgrade --no-cache` |
| Python dependencies | Retains upstream dependency versions | Re-resolved during each build; fixed-package floors cover Pillow, httplib2, pyasn1, and setuptools |
| File capabilities | No capability-bearing Python binary | No capability-bearing Python binary or `libcap` package |
| Mail service | Retains upstream Postfix and password-reset email behavior | Postfix and `sudo` omitted; password-reset email is disabled |
| Build-only tools | Same as upstream | Excluded from the final runtime image |

The hardened rebuild keeps pgAdmin's PostgreSQL 14–18 client utilities and
supported runtime integrations. `libcurl` remains because PostgreSQL's OAuth
client library requires it; it is installed from the freshly upgraded Alpine
package repository rather than inherited from the upstream image.

## Hardened image security model

- Runs as non-root UID `5050` by default and remains compatible with an
  OpenShift arbitrary UID using GID `0`.
- Does not ship `CAP_NET_BIND_SERVICE`, a privileged Python copy, `libcap`,
  `postfix`, `sudo`, or the postfix sudoers rule.
- Uses an explicit `PGADMIN_DISABLE_POSTFIX=1` default and removes the postfix
  startup block entirely, so clearing that variable cannot invoke a missing
  privileged component.
- Builds Python dependencies with `pip --upgrade`, package-security floors,
  and `pip check` before copying the virtual environment into the runtime.
- Publishes SPDX SBOM and SLSA provenance attestations with every image.

The hardened image intentionally keeps pgAdmin's upstream arbitrary-UID
mechanism: `/etc/passwd` is group-writable by GID `0` so a random OpenShift UID
can add its own identity entry. This is required for the supported restricted
OpenShift execution model. Use a read-only root filesystem only with an
NSS-compatible identity strategy or a platform that already provides a passwd
entry.

No image can promise a permanent zero-CVE result. A finding with no vendor fix
cannot be removed safely without replacing the affected component or feature.
The hardened variant removes stale, fixable inherited packages at rebuild time
and records the resulting SBOM so audits can distinguish current fixed findings
from unfixed upstream issues.

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

## Runtime requirements

The first launch needs the standard pgAdmin bootstrap variables:

```text
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=<secret>
```

The service listens on port `8080` by default. Set `PGADMIN_LISTEN_PORT` if a
different unprivileged port is required. A Service or Route should provide
external port mapping; do not add a file capability merely to bind port 80 or
443 inside the container.

Use `PGADMIN_DEFAULT_PASSWORD_FILE` instead of a plaintext environment variable
where the orchestrator can mount a secret file.

## Release automation

Images are published to GHCR only.

The scheduled workflow resolves the latest stable `dpage/pgadmin4` version. It
checks GHCR for the corresponding upstream-compatible tag and builds that image
only if the tag does not exist. It then checks out the exact
`pgadmin-org/pgadmin4` `REL-x_y` source tag and rebuilds the hardened image,
updating both `<version>-hardened` and `latest`. Every build attaches SBOM and
provenance attestations.

The hardened image is rebuilt only when an input that can change its contents
has moved: the pgAdmin source revision, this repository's revision, or any base
image digest. That fingerprint is recorded on the image as the
`io.fyannk.pgadmin.inputs` label and compared against the published `latest`. A
rebuild happens regardless once the published image is more than seven days old,
so a dependency patch with unchanged base images is still picked up.

The workflow retains the ten most-recent untagged GHCR manifests, which are
created when a mutable hardened tag moves. It intentionally creates no daily
date tags, preventing unbounded tagged-image growth.

Published images:

- `ghcr.io/fyannk/pgadmin:<version>`
- `ghcr.io/fyannk/pgadmin:<version>-hardened`
- `ghcr.io/fyannk/pgadmin:latest` (hardened)

## Scope

Neither variant forks the pgAdmin application. The upstream-compatible image
only removes privileged-port binding support. The hardened image additionally
removes the in-container Postfix password-reset delivery path and rebuilds the
runtime from the upstream pgAdmin source.
