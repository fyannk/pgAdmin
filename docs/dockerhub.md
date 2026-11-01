![fyannk/pgadmin logo: an elephant peeking over an application window bearing an ermine](https://raw.githubusercontent.com/fyannk/pgAdmin/main/site/assets/mark-160.png)

# fyannk/pgadmin

**pgAdmin 4 for restricted OpenShift and Kubernetes, with no privileged component left in the image.**

The same pgAdmin release as the official image, without the capability a
restricted platform refuses, so it runs as an unprivileged user or under
whatever UID OpenShift assigns. The hardened variant goes further: rebuilt
from pgAdmin's source with no setuid binary, no `sudo` and no mail server,
and rebuilt again whenever Alpine or Python ship a fix. Every night both are
scanned next to the official image; the
[security report](https://fyannk.github.io/pgAdmin/) shows the result,
including whatever is still left.

> **Its limits.** This does not make pgAdmin itself any safer, and it cannot
> fix a vulnerability before Alpine, Python or the pgAdmin project do. "No
> known, fixable vulnerabilities" means none that the scanners know about and
> that have a fix that can be applied today; the report shows the rest. The
> hardened variant also leaves out password-reset email.

> **Independent.** A personal project, not affiliated with, endorsed by or
> sponsored by the pgAdmin project, the PostgreSQL project, Docker, or any
> company.

## Why use it?

- **Restricted-ready**: no Linux capability and no root step, so it runs under OpenShift's `restricted` profile.
- **Patched sooner**: the hardened variant is rebuilt when a fix lands, and at least once a week.
- **Two choices**: `latest` for the hardened rebuild, `<version>` for the official image with only its capability removed.
- **Proven, not promised**: a public, nightly comparison with the official image.
- **Signed**: each image is signed as it is published, and comes with the list of what is inside it.

## Quick start

```sh
docker run -d --name pgadmin -p 8080:8080 \
  -e PGADMIN_DEFAULT_EMAIL=admin@example.com \
  -e PGADMIN_DEFAULT_PASSWORD=change-me \
  fyannk/pgadmin:latest
```

It listens on `8080` rather than `80`. Everything else documented for the
[official image](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html)
works the same way.

## Tags

| Tag | Points to |
| --- | --- |
| `latest` | The hardened variant of the newest pgAdmin release |
| `<version>-hardened` | The hardened variant of that release, for example `9.18-hardened` |
| `<version>` | The official image of that release with only its capability removed, never rebuilt |

For `linux/amd64`. The images are also on GitHub Container Registry as
`ghcr.io/fyannk/pgadmin`, with the same digests.
[All tags](https://github.com/fyannk/pgAdmin/blob/main/docs/tags.md).

## Learn more

- [Security report](https://fyannk.github.io/pgAdmin/): the nightly comparison, variant by variant.
- [What changes](https://github.com/fyannk/pgAdmin/blob/main/docs/what-changes.md) compared with the official image.
- [Verifying a signature](https://github.com/fyannk/pgAdmin/blob/main/docs/tags.md#verifying-an-image).
- [Source and issues](https://github.com/fyannk/pgAdmin) on GitHub.

---

Apache-2.0; the images also contain pgAdmin, under the PostgreSQL Licence. See
[NOTICE](https://github.com/fyannk/pgAdmin/blob/main/NOTICE).
PostgreSQL® and the Slonik logo are trademarks or registered trademarks of
the PostgreSQL Community Association of Canada. This project is not affiliated
with or endorsed by the Association, nor with the pgAdmin project.
