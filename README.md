# pgadmin

Repackage the official `dpage/pgadmin4` image for OpenShift compatibility.

## Image customization

The image uses this Dockerfile logic:

- base image: `dpage/pgadmin4:${VERSION}`
- remove `/etc/sudoers.d/postfix`
- apply `setcap CAP_NET_BIND_SERVICE=-eip` to `/usr/local/bin/python3.14`

## Automation

GitHub Actions:

- checks Docker Hub for new stable `dpage/pgadmin4` tags on a schedule
- builds this repository image with the same detected version
- publishes to:
  - `ghcr.io/<owner>/pgadmin:<version>`
  - `docker.io/<DOCKERHUB_USERNAME>/pgadmin:<version>`
