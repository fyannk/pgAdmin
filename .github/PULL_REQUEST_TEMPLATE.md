<!--
Thanks for contributing. Keep one focused change per PR. This repository ships
image recipes, not application code: the Dockerfiles are the source of truth
and docs/ explains what the resulting images guarantee.
-->

## What and why

<!-- What does this change, and what problem does it solve? -->

## How it was verified

<!-- Commands you ran, and behavior you confirmed. -->

- [ ] `docker buildx build --check` passes for both recipes
- [ ] The affected image builds against the matching pgAdmin source tree
- [ ] `.github/scripts/check-image.sh` passes on the built image
- [ ] Behaviour confirmed on the built image, not only in the recipe

## Invariants

<!-- These boundaries are the reason the images exist. CI enforces them in
     .github/scripts/check-image.sh, which the publish also runs before it
     moves a tag; confirm the change keeps them. -->

- [ ] Runs as UID `5050` and still starts under an arbitrary UID in GID `0`
- [ ] No capability-bearing interpreter, no `libcap`, no `CAP_NET_BIND_SERVICE`
- [ ] No `postfix` or `sudo`, and the postfix startup block stays removed
- [ ] Build-only tooling stays out of the runtime venv
- [ ] Both recipes pin the same pgAdmin version
- [ ] docs/ (and the README, if the pitch changed) updated if the tags,
      guarantees, or release automation changed
