# Documentation

| Page | For when you want to know |
| --- | --- |
| [What changes](what-changes.md) | Exactly what differs from the official image in each variant, and how to run it |
| [Tags and registries](tags.md) | Which tag to pull, where, and how to verify its signature |
| [Checks and measurement](verification.md) | What is tested before an image ships, and how the nightly report is built |
| [Maintaining](maintaining.md) | Local builds, the publish pipeline, and merge automation |

The live comparison with the official image is at
[fyannk.github.io/pgAdmin](https://fyannk.github.io/pgAdmin/).

[`dockerhub.md`](dockerhub.md) is the overview shown on
[Docker Hub](https://hub.docker.com/r/fyannk/pgadmin). A push to `main` that
changes it updates Docker Hub through
[`dockerhub-description.yml`](../.github/workflows/dockerhub-description.yml).
