# Tags and registries

| Tag | Points to |
| --- | --- |
| `<version>-hardened` | The hardened variant of that pgAdmin release, rebuilt when an input changes and at least weekly |
| `latest` | The hardened variant of the newest pgAdmin release |
| `<version>` | The upstream-compatible variant of that release, published once and never rebuilt |

Only the newest pgAdmin release is rebuilt: once a new release appears, the
previous `<version>-hardened` tag stops updating. See
[What changes](what-changes.md) for how the variants differ.

```text
docker pull ghcr.io/fyannk/pgadmin:latest
docker pull fyannk/pgadmin:latest
```

Images are published to GHCR and Docker Hub, for `linux/amd64`. A tag
resolves to the same image digest on either.

## Verifying an image

Every image is signed with [cosign](https://github.com/sigstore/cosign),
keylessly: the signature is bound to the publishing workflow's GitHub identity
and recorded in Sigstore's public transparency log, so there is no key to leak
or rotate.

```text
cosign verify ghcr.io/fyannk/pgadmin:latest \
  --certificate-identity https://github.com/fyannk/pgAdmin/.github/workflows/build-and-publish.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The signer identity is the repository as GitHub spells it, `fyannk/pgAdmin`;
cosign compares it exactly, so the lower-case package name will not match.

The signature is stored on GHCR. A Docker Hub tag serves the same digest, so
check that digest against GHCR:

```text
digest="$(docker buildx imagetools inspect fyannk/pgadmin:latest --format '{{json .Manifest}}' | jq -r .digest)"
cosign verify "ghcr.io/fyannk/pgadmin@${digest}" \
  --certificate-identity https://github.com/fyannk/pgAdmin/.github/workflows/build-and-publish.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The signature covers the image index, and through it the image, its SBOM and
its provenance attestation. Hardened images published before signing was
introduced are signed when they are next rebuilt, which happens at least
weekly. An upstream-compatible `<version>` published before then is never
rebuilt, so it stays unsigned; the next pgAdmin release is the first signed
one.
