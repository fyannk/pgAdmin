# syntax=docker/dockerfile:1.7

# Build with the matching pgAdmin source tree as the context, for example:
# docker build --pull -f Dockerfile ../pgadmin4
ARG VERSION=9.17
ARG PYTHON_IMAGE=python:3.14-alpine
ARG ALPINE_IMAGE=alpine:3.24

########################################################################
# Build the JavaScript assets from source.
########################################################################
FROM ${ALPINE_IMAGE} AS app-builder

RUN apk add --no-cache \
    autoconf \
    automake \
    bash \
    g++ \
    git \
    libc6-compat \
    libjpeg-turbo-dev \
    libpng-dev \
    libtool \
    make \
    nasm \
    nodejs \
    npm \
    yarn \
    zlib-dev

COPY web /pgadmin4/web
WORKDIR /pgadmin4/web

RUN --mount=type=bind,source=.git,target=/pgadmin4/.git \
  --mount=type=tmpfs,target=node_modules \
  --mount=type=tmpfs,target=pgadmin/static/js/generated/.cache \
  export CPPFLAGS="-DPNG_ARM_NEON_OPT=0" && \
  npm install -g corepack && \
  corepack enable && \
  yarn set version berry && \
  yarn set version "$(node -p "require('./package.json').packageManager.split('@')[1]")" && \
  yarn install && \
  yarn run bundle && \
  rm -rf yarn.lock package.json .[^.]* babel.cfg webpack.* jest.config.js babel.*

########################################################################
# Build Python dependencies from source requirements, resolving to current
# patched releases. Security floors protect packages fixed after pgAdmin's
# release tag was cut.
########################################################################
FROM ${PYTHON_IMAGE} AS python-builder

COPY requirements.txt /tmp/requirements.txt

RUN apk add --no-cache --virtual .build-deps \
    build-base \
    cargo \
    krb5-dev \
    libffi-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    openssl-dev \
    postgresql-dev \
    rust \
    zlib-dev && \
  printf '%s\n' \
    'Pillow>=12.3.0' \
    'httplib2>=0.32.0' \
    'pyasn1>=0.6.4' \
    'setuptools>=83.0.0' \
    > /tmp/security-constraints.txt
# --without-pip keeps pip and wheel out of the runtime venv: the interpreter
# reaches the base image's pip through --system-site-packages for the install,
# so neither ends up as a scannable distribution in the shipped image.
RUN python3 -m venv --system-site-packages --without-pip /venv && \
  /venv/bin/python3 -m pip install --no-cache-dir --upgrade \
    --constraint /tmp/security-constraints.txt \
    -r /tmp/requirements.txt \
    gunicorn==23.0.0 && \
  /venv/bin/python3 -m pip check && \
  apk del .build-deps && \
  find /venv -type d -name '__pycache__' -prune -exec rm -rf {} +

########################################################################
# Build the help documentation. Documentation-only dependencies stay in this
# stage and are never copied into the runtime image.
########################################################################
FROM python-builder AS docs-builder

COPY docs /pgadmin4/docs
COPY web /pgadmin4/web

RUN /venv/bin/python3 -m pip install --no-cache-dir --upgrade \
    sphinx \
    sphinxcontrib-youtube && \
  rm -rf /pgadmin4/docs/en_US/_build && \
  LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    /venv/bin/sphinx-build /pgadmin4/docs/en_US /pgadmin4/docs/en_US/_build/html && \
  rm -rf /pgadmin4/docs/en_US/_build/html/.doctrees \
       /pgadmin4/docs/en_US/_build/html/_sources \
       /pgadmin4/docs/en_US/_build/html/_static/*.png

########################################################################
# Keep the upstream PostgreSQL client-tool coverage without retaining builders.
########################################################################
FROM postgres:14-alpine3.24 AS pg14-builder
FROM postgres:15-alpine3.24 AS pg15-builder
FROM postgres:16-alpine3.24 AS pg16-builder
FROM postgres:17-alpine3.24 AS pg17-builder
FROM postgres:18-alpine3.24 AS pg18-builder

FROM ${ALPINE_IMAGE} AS tools-builder

COPY --from=pg14-builder /usr/local/bin/pg_dump /usr/local/pgsql/pgsql-14/
COPY --from=pg14-builder /usr/local/bin/pg_dumpall /usr/local/pgsql/pgsql-14/
COPY --from=pg14-builder /usr/local/bin/pg_restore /usr/local/pgsql/pgsql-14/
COPY --from=pg14-builder /usr/local/bin/psql /usr/local/pgsql/pgsql-14/
COPY --from=pg15-builder /usr/local/bin/pg_dump /usr/local/pgsql/pgsql-15/
COPY --from=pg15-builder /usr/local/bin/pg_dumpall /usr/local/pgsql/pgsql-15/
COPY --from=pg15-builder /usr/local/bin/pg_restore /usr/local/pgsql/pgsql-15/
COPY --from=pg15-builder /usr/local/bin/psql /usr/local/pgsql/pgsql-15/
COPY --from=pg16-builder /usr/local/bin/pg_dump /usr/local/pgsql/pgsql-16/
COPY --from=pg16-builder /usr/local/bin/pg_dumpall /usr/local/pgsql/pgsql-16/
COPY --from=pg16-builder /usr/local/bin/pg_restore /usr/local/pgsql/pgsql-16/
COPY --from=pg16-builder /usr/local/bin/psql /usr/local/pgsql/pgsql-16/
COPY --from=pg17-builder /usr/local/bin/pg_dump /usr/local/pgsql/pgsql-17/
COPY --from=pg17-builder /usr/local/bin/pg_dumpall /usr/local/pgsql/pgsql-17/
COPY --from=pg17-builder /usr/local/bin/pg_restore /usr/local/pgsql/pgsql-17/
COPY --from=pg17-builder /usr/local/bin/psql /usr/local/pgsql/pgsql-17/
COPY --from=pg18-builder /usr/local/bin/pg_dump /usr/local/pgsql/pgsql-18/
COPY --from=pg18-builder /usr/local/bin/pg_dumpall /usr/local/pgsql/pgsql-18/
COPY --from=pg18-builder /usr/local/bin/pg_restore /usr/local/pgsql/pgsql-18/
COPY --from=pg18-builder /usr/local/bin/psql /usr/local/pgsql/pgsql-18/

########################################################################
# Assemble a patched runtime with only application runtime dependencies.
########################################################################
FROM ${PYTHON_IMAGE} AS runtime

ARG VERSION
ARG PYTHON_IMAGE
ARG SOURCE_REVISION=""

ENV SUMMARY="FYannK pgAdmin for OpenShift" \
  DESCRIPTION="Source-built pgAdmin for restricted OpenShift-style deployments" \
  PGADMIN_DISABLE_POSTFIX=1 \
  PYTHONPATH=/pgadmin4

LABEL summary="$SUMMARY" \
    description="$DESCRIPTION" \
    io.k8s.display-name="$SUMMARY" \
    io.k8s.description="$DESCRIPTION" \
    name="pgAdmin4" \
    org.opencontainers.image.title="pgAdmin4" \
    org.opencontainers.image.description="$DESCRIPTION" \
    org.opencontainers.image.url="https://github.com/fyannk/pgadmin" \
    org.opencontainers.image.source="https://github.com/fyannk/pgadmin" \
    org.opencontainers.image.revision="$SOURCE_REVISION" \
    org.opencontainers.image.vendor="fyannk" \
    org.opencontainers.image.version="$VERSION" \
    org.opencontainers.image.base.name="$PYTHON_IMAGE" \
    io.fyannk.pgadmin.variant="hardened" \
    vendor="fyannk" \
    url="https://github.com/fyannk/pgadmin" \
    version="$VERSION" \
    release="2"

RUN apk upgrade --no-cache && \
  apk add --no-cache \
    bash \
    krb5-libs \
    libcurl \
    libedit \
    libjpeg-turbo \
    libldap \
    shadow \
    su-exec \
    tzdata && \
  rm -rf /var/cache/apk/*

COPY --from=python-builder /venv /venv
COPY --from=tools-builder /usr/local/pgsql /usr/local/
COPY --from=pg18-builder /usr/local/lib/libpq.so.5.18 /usr/local/lib/libpq-oauth-18.so /usr/lib/liblz4.so.1.10.0 /usr/lib/

RUN ln -s libpq.so.5.18 /usr/lib/libpq.so.5 && \
  ln -s libpq.so.5.18 /usr/lib/libpq.so && \
  ln -s liblz4.so.1.10.0 /usr/lib/liblz4.so.1

WORKDIR /pgadmin4

COPY --from=app-builder /pgadmin4/web /pgadmin4
COPY --from=docs-builder /pgadmin4/docs/en_US/_build/html/ /pgadmin4/docs
COPY pkg/docker/run_pgadmin.py pkg/docker/gunicorn_config.py /pgadmin4/
COPY pkg/docker/entrypoint.sh /entrypoint.sh
COPY LICENSE /pgadmin4/LICENSE

RUN find / -type d -name '__pycache__' -prune -exec rm -rf {} + && \
  useradd -r -u 5050 -g root -s /sbin/nologin pgadmin && \
  mkdir -p /run/pgadmin /var/lib/pgadmin && \
  chown pgadmin:root /run/pgadmin /var/lib/pgadmin && \
  chmod g=u /run/pgadmin /var/lib/pgadmin && \
  touch /pgadmin4/config_distro.py && \
  chown pgadmin:root /pgadmin4/config_distro.py && \
  chmod g=u /pgadmin4/config_distro.py && \
  chmod g=u /etc/passwd && \
  sed -i '/^# Start Postfix to handle password resets etc\.$/,/^fi$/d' /entrypoint.sh

USER 5050

VOLUME /var/lib/pgadmin
EXPOSE 8080 8443

ENTRYPOINT ["/entrypoint.sh"]
