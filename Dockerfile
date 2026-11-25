# syntax=docker/dockerfile:1.7

# Build with the matching pgAdmin source tree as the context, for example:
# docker build --pull -f Dockerfile ../pgadmin4
ARG VERSION=9.18
ARG PYTHON_IMAGE=python:3.15-alpine
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

# webpack leaves nothing a scanner can read: the bundle carries no package
# metadata and package.json and yarn.lock are removed below. This records every
# npm package whose code can end up in the bundle as a bare package.json, which
# syft's default image catalogers pick up. That is the dependencies closure, not
# yarn.lock, which also lists the build and test tooling that never ships. The
# one dev dependency compiled into the bundle is core-js: babel's
# useBuiltIns: "usage" injects its polyfills. Overreporting a package webpack
# tree-shook away is the safe direction; missing one that shipped is not.
COPY <<'EOF' /usr/local/share/npm-sbom.js
const fs = require('fs');
const path = require('path');

const out = process.argv[2];
const bundledDevDependencies = ['core-js'];
const root = JSON.parse(fs.readFileSync('package.json', 'utf8'));

for (const name of bundledDevDependencies) {
  if (!(root.devDependencies || {})[name]) {
    throw new Error(`${name} is no longer a dev dependency; review bundledDevDependencies`);
  }
}

// Node's own lookup: the nearest node_modules/<name> walking up from the dependent.
function locate(name, from) {
  for (let dir = from; ; dir = path.dirname(dir)) {
    const manifest = path.join(dir, 'node_modules', name, 'package.json');
    if (fs.existsSync(manifest)) return manifest;
    if (path.dirname(dir) === dir) return null;
  }
}

const seen = new Set();
const queue = [];
function visit(names, from, required) {
  for (const name of names) {
    const manifest = locate(name, from);
    if (!manifest) {
      if (required) throw new Error(`${name}, needed from ${from}, is not installed`);
      continue;
    }
    if (!seen.has(manifest)) {
      seen.add(manifest);
      queue.push(manifest);
    }
  }
}

const cwd = process.cwd();
visit(Object.keys(root.dependencies || {}), cwd, true);
visit(bundledDevDependencies, cwd, true);
visit(Object.keys(root.optionalDependencies || {}), cwd, false);

const packages = new Map();
while (queue.length) {
  const manifest = queue.shift();
  const pkg = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  const dir = path.dirname(manifest);
  if (pkg.name && pkg.version) {
    packages.set(`${pkg.name}@${pkg.version}`, {
      name: pkg.name,
      version: pkg.version,
      ...(pkg.license ? { license: pkg.license } : {}),
    });
  }
  visit(Object.keys(pkg.dependencies || {}), dir, true);
  visit(Object.keys(pkg.optionalDependencies || {}), dir, false);
  visit(Object.keys(pkg.peerDependencies || {}), dir, false);
}

for (const [id, pkg] of packages) {
  const dir = path.join(out, id);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify(pkg) + '\n');
}
console.log(`Recorded ${packages.size} npm packages in ${out}`);
EOF

# Security floors for bundled npm packages fixed after pgAdmin's release tag was
# cut, the npm counterpart of the Python floors below. They go in as yarn
# resolutions, which pgAdmin already uses for the same purpose, and only for a
# package upstream has not pinned itself: once it does, its choice wins. A floor
# must be older than the npmMinimalAgeGate in .yarnrc.yml or the install fails.
COPY <<'EOF' /usr/local/share/npm-security-floors.js
const fs = require('fs');

const floors = {
  'follow-redirects': '^1.16.2',
  'fast-uri': '^3.1.9',
};

const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.resolutions = pkg.resolutions || {};
for (const [name, range] of Object.entries(floors)) {
  if (pkg.resolutions[name]) {
    console.log(`${name}: upstream resolution ${pkg.resolutions[name]} kept, floor ${range} skipped`);
    continue;
  }
  pkg.resolutions[name] = range;
  console.log(`${name}: floor ${range}`);
}
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
EOF

RUN --mount=type=bind,source=.git,target=/pgadmin4/.git \
  --mount=type=tmpfs,target=node_modules \
  --mount=type=tmpfs,target=pgadmin/static/js/generated/.cache \
  export CPPFLAGS="-DPNG_ARM_NEON_OPT=0" && \
  npm install -g corepack && \
  corepack enable && \
  yarn set version berry && \
  yarn set version "$(node -p "require('./package.json').packageManager.split('@')[1]")" && \
  node /usr/local/share/npm-security-floors.js && \
  yarn install && \
  yarn run bundle && \
  node /usr/local/share/npm-sbom.js /sbom/npm && \
  rm -rf yarn.lock package.json .[^.]* babel.cfg webpack.* jest.config.js babel.*

########################################################################
# Build Python dependencies from source requirements, resolving to current
# patched releases. Security floors protect packages fixed after pgAdmin's
# release tag was cut.
########################################################################
FROM ${PYTHON_IMAGE} AS python-builder

COPY requirements.txt /tmp/requirements.txt

# Floors cannot lift an exact pin, so pins that carry a fixed
# critical are rewritten to the release upstream master already pins. Each
# substitution matches only the vulnerable pin and stops applying once the
# release tag catches up; the matching floor fails the build if a pin is
# still vulnerable and no substitution covered it.
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
    'Authlib>=1.9.1' \
    'certifi>=2026.10.18' \
    'urllib3>=2.8.0' \
    > /tmp/security-constraints.txt && \
  sed -i \
    -e 's/^Authlib==1\.8\.\*;/Authlib==1.9.*;/' \
    -e 's/^certifi==2026\.7\.22$/certifi==2026.10.23/' \
    -e 's/^urllib3==2\.7\.\*;/urllib3==2.8.*;/' \
    /tmp/requirements.txt
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
# Record the C libraries compiled into CPython or into a wheel, which carry no
# package record: OpenSSL in cryptography, Expat in CPython, libpng in Pillow.
# As for the PostgreSQL tools below, an ELF package note is what syft's default
# image catalogers read. It goes on an empty shared object per library rather
# than on the wheels' own files, whose hashes pip records.
# cryptography's own list of its Rust crates is copied under a name the SBOM
# generator reads; grype does not scan it in an image.
########################################################################
FROM python-builder AS bundled-libraries

RUN apk add --no-cache gcc && /venv/bin/python3 - <<'EOF'
import glob, json, os, pyexpat, re, shutil, subprocess, sys

from cryptography.hazmat.backends.openssl import backend

out = "/sbom/bundled"
os.makedirs(out)
site = glob.glob("/venv/lib/python3*/site-packages")[0]

libraries = [
    ("openssl", "openssl", backend.openssl_version_text().split()[1]),
    ("libexpat", "libexpat_project", pyexpat.EXPAT_VERSION.removeprefix("expat_")),
]
for path in glob.glob(f"{site}/pillow.libs/*"):
    if found := re.search(r"/libpng16-[0-9a-f]+\.so\.16\.([0-9]+)\.", path):
        libraries.append(("libpng", "libpng", f"1.6.{found[1]}"))

for name, vendor, version in libraries:
    if not re.fullmatch(r"[0-9]+(\.[0-9]+)+[a-z]?", version):
        sys.exit(f"unexpected {name} version {version!r}")
    note = json.dumps({
        "type": "generic", "name": name, "version": version,
        "cpe": f"cpe:2.3:a:{vendor}:{name}:{version}:*:*:*:*:*:*:*",
    })
    with open("/tmp/note.json", "w") as f:
        f.write(note)
    with open("/tmp/note.s", "w") as f:
        f.write(f"""
            .section .note.package,"",%note
            .balign 4
            .long 4
            .long {len(note)}
            .long 0xcafe1a7e
            .ascii "FDO\\0"
            .incbin "/tmp/note.json"
            .balign 4
        """)
    subprocess.run(["gcc", "-shared", "-nostdlib", "-o", f"{out}/{name}.so", "/tmp/note.s"], check=True)

for path in glob.glob(f"{site}/cryptography-*.dist-info/sboms/cryptography-rust.cyclonedx.json"):
    shutil.copy(path, f"{out}/cryptography-rust.cdx.json")
EOF

########################################################################
# Build the help documentation. Documentation-only dependencies stay in this
# stage and are never copied into the runtime image.
########################################################################
FROM python-builder AS docs-builder

COPY docs /pgadmin4/docs
COPY web /pgadmin4/web

# Since 9.19 the docs build imports psycopg, through config.py, and psycopg's C
# extension needs libpq.so.5. The copy postgresql-dev pulled in went with
# .build-deps. It is only needed here: the runtime image gets its libpq from
# pg18-builder.
RUN apk add --no-cache libpq && \
  /venv/bin/python3 -m pip install --no-cache-dir --upgrade \
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
COPY --from=pg18-builder /usr/local/lib/libpq.so.5.18 /usr/local/lib/libpq-oauth-18.so /usr/local/pgsql-lib/

# The official postgres images build PostgreSQL from source, so these files
# carry no package record and a scanner reports nothing for them. Each one gets
# an ELF package note (https://systemd.io/ELF_PACKAGE_METADATA/), which syft's
# default image catalogers read, naming it postgresql at the version compiled
# into it. The CPE is what grype matches PostgreSQL advisories on. libpq has no
# version string of its own and comes from the same build as pgsql-18/psql.
RUN apk add --no-cache binutils && sh -eu <<'EOF'
note() {
  file="$1"
  version="$2"
  json="{\"type\":\"generic\",\"name\":\"postgresql\",\"version\":\"${version}\",\"license\":\"PostgreSQL\",\"cpe\":\"cpe:2.3:a:postgresql:postgresql:${version}:*:*:*:*:*:*:*\"}"
  len=$(printf '%s' "$json" | wc -c)
  pad=$(( (4 - len % 4) % 4 ))
  # Note header: namesz, descsz, type, then the "FDO" owner, all little-endian
  # like the binaries on both published architectures.
  le32() {
    printf "\\$(printf %03o $(($1 & 255)))\\$(printf %03o $((($1 >> 8) & 255)))\\$(printf %03o $((($1 >> 16) & 255)))\\$(printf %03o $((($1 >> 24) & 255)))"
  }
  { le32 4; le32 $((len + pad)); le32 3405650558; printf 'FDO\0'; printf '%s' "$json"; head -c "$pad" /dev/zero; } > /tmp/note
  objcopy --add-section .note.package=/tmp/note --set-section-flags .note.package=noload,readonly "$file"
}

compiled_version() {
  version="$(grep -aoE '\(PostgreSQL\) [0-9]+\.[0-9]+' "$1" | head -n1 | cut -d' ' -f2)"
  if [ -z "$version" ]; then
    echo "No PostgreSQL version found in $1" >&2
    exit 1
  fi
  echo "$version"
}

for dir in /usr/local/pgsql/pgsql-*; do
  major="${dir##*-}"
  for file in "$dir"/*; do
    version="$(compiled_version "$file")"
    if [ "${version%%.*}" != "$major" ]; then
      echo "$file reports PostgreSQL $version, expected $major" >&2
      exit 1
    fi
    note "$file" "$version"
  done
done

version="$(compiled_version /usr/local/pgsql/pgsql-18/psql)"
for file in /usr/local/pgsql-lib/*; do
  note "$file" "$version"
done
EOF

########################################################################
# Assemble a patched runtime with only application runtime dependencies.
########################################################################
FROM ${PYTHON_IMAGE} AS runtime

ARG VERSION
ARG PYTHON_IMAGE
ARG SOURCE_REVISION=""
# Fingerprint of every input that can change this image's contents. The publish
# workflow compares it against the published image to avoid pushing a rebuild
# that would only differ by timestamp.
ARG BUILD_INPUTS=""

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
    io.fyannk.pgadmin.inputs="$BUILD_INPUTS" \
    vendor="fyannk" \
    url="https://github.com/fyannk/pgadmin" \
    version="$VERSION" \
    release="3"

RUN apk upgrade --no-cache && \
  apk add --no-cache \
    bash \
    krb5-libs \
    libcurl \
    libedit \
    libjpeg-turbo \
    libldap \
    lz4-libs \
    shadow \
    su-exec \
    tzdata && \
  rm -rf /var/cache/apk/*

COPY --from=python-builder /venv /venv
COPY --from=tools-builder /usr/local/pgsql /usr/local/
COPY --from=tools-builder /usr/local/pgsql-lib/ /usr/lib/

RUN ln -s libpq.so.5.18 /usr/lib/libpq.so.5 && \
  ln -s libpq.so.5.18 /usr/lib/libpq.so

WORKDIR /pgadmin4

COPY --from=app-builder /pgadmin4/web /pgadmin4
COPY --from=docs-builder /pgadmin4/docs/en_US/_build/html/ /pgadmin4/docs
COPY pkg/docker/run_pgadmin.py pkg/docker/gunicorn_config.py /pgadmin4/
COPY pkg/docker/entrypoint.sh /entrypoint.sh
COPY LICENSE /pgadmin4/LICENSE
COPY --from=app-builder /sbom/npm /usr/share/sbom/npm

# pgAdmin runs from its source tree, which has no package metadata, so
# advisories filed against pgadmin4 would never match the image. A minimal
# dist-info names it the way PyPI does. It sits outside PYTHONPATH, so it is
# only seen by scanners, and its version comes from the source being shipped,
# checked against the version the build was asked for.
RUN release="$(sed -n 's/^APP_RELEASE = \([0-9]*\)$/\1/p' /pgadmin4/version.py)" && \
  revision="$(sed -n 's/^APP_REVISION = \([0-9]*\)$/\1/p' /pgadmin4/version.py)" && \
  version="${release}.${revision}" && \
  if [ -n "${VERSION}" ] && [ "${version}" != "${VERSION}" ]; then \
    echo "Source is pgAdmin ${version}, build asked for ${VERSION}" >&2; exit 1; \
  fi && \
  mkdir -p "/usr/share/sbom/python/pgadmin4-${version}.dist-info" && \
  printf '%s\n' \
    'Metadata-Version: 2.1' \
    'Name: pgadmin4' \
    "Version: ${version}" \
    'License: PostgreSQL' \
    'Home-page: https://www.pgadmin.org/' \
    > "/usr/share/sbom/python/pgadmin4-${version}.dist-info/METADATA"

# See bundled-libraries, above.
COPY --from=bundled-libraries /sbom/bundled /usr/share/sbom/bundled

# shadow is kept for the entrypoint's root-only usermod, but none of the
# setuid helpers it and linux-pam install are needed at runtime.
#
# The base image's own pip goes too. The venv was built without one, and
# nothing in pgAdmin, its dependencies or the entrypoint invokes pip, but the
# venv sees system site-packages, so the base's copy stayed importable and
# shipped its own vendored setuptools, msgpack and urllib3, older than the
# venv's. ensurepip's bundled wheel is the same pip again.
RUN rm -rf /usr/local/lib/python3*/site-packages/pip \
    /usr/local/lib/python3*/site-packages/pip-*.dist-info \
    /usr/local/lib/python3*/ensurepip/_bundled \
    /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.* && \
  find / -type d -name '__pycache__' -prune -exec rm -rf {} + && \
  find / -xdev -type f -perm /6000 -exec chmod a-s {} + && \
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
