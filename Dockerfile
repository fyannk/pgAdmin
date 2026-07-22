ARG VERSION=9.16
FROM dpage/pgadmin4:${VERSION}

ENV SUMMARY="FYannK pgAdmin Container Image." \
    DESCRIPTION="Custom pgAdmin image for openshift compatibility."

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.display-name="$SUMMARY" \
      io.k8s.description="$DESCRIPTION" \
      name="pgAdmin4" \
      vendor="fyannk" \
      url="https://github.com/fyannk/pgadmin" \
      version="$VERSION" \
      release="1"

USER root
RUN rm -vf /etc/sudoers.d/postfix \
  && setcap CAP_NET_BIND_SERVICE=-eip /usr/local/bin/python3.14
USER pgadmin
