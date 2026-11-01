# What changes compared with the official image

Both variants package the same pgAdmin release as the official
[`dpage/pgadmin4`](https://hub.docker.com/r/dpage/pgadmin4) image. They differ
in how much of that image they keep.

## Variants

| Tag | Variant | Use when |
| --- | --- | --- |
| `<version>` | Upstream-compatible no-cap | Immutable release image. It is published once when the matching official `dpage/pgadmin4` release first appears, with only its privileged Python capability removed. |
| `<version>-hardened` | Source-rebuilt hardened image | Mutable rebuild of that pgAdmin release with refreshed OS and Python dependencies. |
| `latest` | Source-rebuilt hardened image | Mutable rebuild of the newest supported pgAdmin release. This tag always points to the hardened variant. |

Both variants remove privileged-port support and therefore default to port
`8080` or `8443` when `PGADMIN_LISTEN_PORT` is not set. Expose them through a
Service or Route rather than restoring a file capability.

## Side by side

| Area | `<version>` upstream-compatible | `<version>-hardened` |
| --- | --- | --- |
| Application | Official prebuilt `dpage/pgadmin4:<version>` | Exact `REL-x_y` pgAdmin source release rebuilt in CI |
| Image delta | Removes only the dedicated `python3-cap` binary that grants `CAP_NET_BIND_SERVICE` | Replaces the base image, rebuilds the application, and removes privileged components |
| OS packages | Retains the upstream package snapshot | Fresh base images (`--pull`) plus `apk upgrade --no-cache` |
| Python dependencies | Retains upstream dependency versions | Re-resolved during each build; fixed-package floors cover Pillow, httplib2, pyasn1, setuptools, Authlib, certifi, and urllib3, with vulnerable exact pins lifted to upstream master's release |
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
- Ships no setuid or setgid binaries.
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

Every pull request rebuilds the hardened image and asserts these properties
against the result, so a change that reintroduces a privileged component or
leaves build-only tooling in the runtime fails before it merges. The scan gate
blocks on critical findings with an applicable fix that the change introduces;
one already in the published image is tracked by a nightly-updated issue, and
every other finding with a fix is published to the repository's code scanning
results. The full inventory, fixed or not, is on the nightly
[security report](https://fyannk.github.io/pgAdmin/).

No image can promise a permanent zero-CVE result. A finding with no vendor fix
cannot be removed safely without replacing the affected component or feature.
The hardened variant removes stale, fixable inherited packages at rebuild time
and records the resulting SBOM so audits can distinguish current fixed findings
from unfixed upstream issues.

## Running it

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

## Scope

Neither variant forks the pgAdmin application. The upstream-compatible image
only removes privileged-port binding support. The hardened image additionally
removes the in-container Postfix password-reset delivery path and rebuilds the
runtime from the upstream pgAdmin source.
