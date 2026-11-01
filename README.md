<p align="center">
  <img src="site/assets/mark.svg" width="140" alt="fyannk/pgadmin logo: an elephant peeking over an application window bearing an ermine">
</p>

<h1 align="center">pgadmin</h1>

<p align="center">
  <strong>pgAdmin 4 for restricted OpenShift and Kubernetes, with no privileged component left in the image.</strong><br>
  Rebuilt as soon as a fix lands, signed, and measured against the official image every night, in public.
</p>

<p align="center">
  <a href="https://fyannk.github.io/pgAdmin/"><img src="https://img.shields.io/badge/security_report-nightly-090c0a?style=flat-square&labelColor=1b231d" alt="Nightly security report"></a>
  <a href="https://github.com/fyannk/pgAdmin/actions/workflows/ci.yml"><img src="https://github.com/fyannk/pgAdmin/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="docs/tags.md#verifying-an-image"><img src="https://img.shields.io/badge/signed-cosign-090c0a?style=flat-square&labelColor=1b231d" alt="Signed with cosign"></a>
  <a href="https://github.com/fyannk/pgAdmin/pkgs/container/pgadmin"><img src="https://img.shields.io/badge/ghcr.io-fyannk%2Fpgadmin-090c0a?style=flat-square&logo=github&logoColor=b3bf3a&labelColor=1b231d" alt="On GitHub Container Registry"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-090c0a?style=flat-square&labelColor=1b231d" alt="Apache-2.0 license"></a>
  <a href="https://hub.docker.com/r/fyannk/pgadmin"><img src="https://img.shields.io/badge/docker_hub-fyannk%2Fpgadmin-090c0a?style=flat-square&logo=docker&logoColor=b3bf3a&labelColor=1b231d" alt="On Docker Hub"></a>
</p>

The same pgAdmin release as the official image, without the capability a
restricted platform refuses, so it runs as an unprivileged user or under
whatever UID OpenShift assigns. The hardened variant goes further: rebuilt
from pgAdmin's source with no setuid binary, no `sudo` and no mail server,
and rebuilt again whenever Alpine or Python ship a fix. Every night both are
scanned next to the official image; the [report](https://fyannk.github.io/pgAdmin/) shows the
result, including whatever is still left.

> [!IMPORTANT]
> This does not make pgAdmin itself any safer, and it cannot fix a
> vulnerability before Alpine, Python or the pgAdmin project do. "No known,
> fixable vulnerabilities" means none that the scanners know about and that
> have a fix that can be applied today; the report shows the rest, and how
> current the scanners' data is. The hardened variant also leaves out
> password-reset email, which needs the bundled mail server.

> [!NOTE]
> An independent, personal project. It is not affiliated with, endorsed by or
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
  ghcr.io/fyannk/pgadmin:latest
```

It listens on `8080` rather than `80`, since binding a privileged port is
exactly what it gives up. Everything else documented for the
[official image](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html)
works the same way. The images are also on Docker Hub as `fyannk/pgadmin`.

## Project status

Maintained. The newest pgAdmin release is published, for `linux/amd64`.

## Documentation

- [Security report](https://fyannk.github.io/pgAdmin/): the nightly comparison, variant by variant.
- [What changes](docs/what-changes.md) compared with the official image, and how to run it.
- [Tags and registries](docs/tags.md), and how to verify a signature.
- [How images are checked](docs/verification.md) before they ship, and how they are measured.
- [Maintaining](docs/maintaining.md): local builds and the publishing pipeline.

## Contributing

Contributions are welcome. Read
[CONTRIBUTING.md](https://github.com/fyannk/.github/blob/main/CONTRIBUTING.md)
first. For larger changes, open an issue before writing code.

## Security

Report vulnerabilities privately, as described in [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE). The images contain pgAdmin, under the
PostgreSQL Licence, and the official image's own files; see [NOTICE](NOTICE).

---

<sub>PostgreSQL® and the Slonik logo are trademarks or registered trademarks of
the PostgreSQL Community Association of Canada. This project is not affiliated
with or endorsed by the Association, nor with the
[pgAdmin project](https://www.pgadmin.org/), whose release it packages.</sub>
