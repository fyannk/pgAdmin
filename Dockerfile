ARG VERSION=9.16
FROM dpage/pgadmin4:${VERSION}
ARG VERSION

ENV SUMMARY="FYannK pgAdmin for OpenShift" \
  DESCRIPTION="Thin wrapper around dpage/pgadmin4 for OpenShift-style deployments; clears CAP_NET_BIND_SERVICE to stay closer to a least-privilege runtime model."

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.display-name="$SUMMARY" \
      io.k8s.description="$DESCRIPTION" \
      name="pgAdmin4" \
      org.opencontainers.image.title="pgAdmin4" \
      org.opencontainers.image.description="$DESCRIPTION" \
      org.opencontainers.image.url="https://github.com/fyannk/pgadmin" \
      org.opencontainers.image.source="https://github.com/fyannk/pgadmin" \
      org.opencontainers.image.vendor="fyannk" \
      org.opencontainers.image.version="$VERSION" \
      org.opencontainers.image.base.name="dpage/pgadmin4:${VERSION}" \
      vendor="fyannk" \
      url="https://github.com/fyannk/pgadmin" \
      version="$VERSION" \
      release="1"

USER root
RUN rm -vf /etc/sudoers.d/postfix \
  && setcap CAP_NET_BIND_SERVICE=-eip /usr/local/bin/python3.14
USER pgadmin
