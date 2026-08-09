# Security Policy

## Scope

This repository publishes container images. It contains no pgAdmin application
code: both variants package releases of
[pgadmin-org/pgadmin4](https://github.com/pgadmin-org/pgadmin4).

- A flaw in pgAdmin itself belongs upstream. Report it to the pgAdmin project.
- A flaw in how these images are assembled or configured belongs here: a
  restriction that does not hold, a privileged component that should not be
  present, a capability the runtime should not carry, or a packaging mistake
  that exposes something the upstream image does not.

## Supported versions

Fixes land in the hardened image. It is rebuilt from the newest supported
pgAdmin release and republished as `<version>-hardened` and `latest`. Older
`<version>-hardened` tags are not rebuilt.

The upstream-compatible `<version>` image is immutable by design: it is
published once, when the matching official release first appears, and is never
patched afterwards. Its vulnerability count only grows. Deploy the hardened
variant if that matters to you.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/fyannk/pgAdmin/security/advisories/new)
so the report and any supporting material remain confidential.

Include the affected tag and image digest, the deployment configuration,
impact, and reproduction steps. Do not include live credentials, connection
strings, or other secrets in the report.

Public disclosure should wait until a fix or mitigation is available and a
coordinated disclosure date has been agreed.

## How scan findings are triaged

Every pull request rebuilds the hardened image, scans it with grype, and
publishes the full result to this repository's code scanning alerts. The
alerts are an inventory of what is present, not a queue of outstanding work.

**CI blocks on critical findings that have an applicable fix.** That is the
only class where a change to this repository can turn the check green, so it
is the only class worth failing a build over. Gating on everything below it
would leave a required check permanently red and teach people to ignore it.

Findings are left open, and are expected to be left open, when:

- **No fix is published.** Rebuilding cannot clear them. The scheduled rebuild
  applies `apk upgrade` and re-resolves Python dependencies, so a fix is
  picked up automatically once it exists — no manual tracking required.
- **The only fix is a pre-release.** CPython advisories are regularly marked
  fixed in an alpha, beta, or release candidate of the next minor. Shipping a
  Python pre-release in a production image is the worse trade.
- **The fix is outside a pin pgAdmin declares.** `requirements.txt` pins
  direct dependencies. Overriding a pin to clear a finding risks breaking the
  application, so it is done only when the finding is genuinely reachable.

An alert is dismissed only when the vulnerable code path is demonstrably
unreachable in this image, and the dismissal comment records the evidence.
"No fix available" is not a reason to dismiss: those findings stay visible so
they resolve on their own when upstream ships.

To see only what is actionable:

```text
grype ghcr.io/fyannk/pgadmin:latest --only-fixed
```

Run an unrestricted scan as well when policy requires it. A finding with no
fixed version needs a documented risk decision rather than an image-layer
cleanup.
