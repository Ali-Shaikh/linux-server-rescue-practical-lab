# Running the lab in GitHub Codespaces

GitHub Codespaces provides the quickest path into the lab when Docker is not
available locally. Select the badge in the main README to create a new
codespace or resume a matching one.

## What is provisioned

The repository's [dev container configuration](../.devcontainer/devcontainer.json)
uses an Ubuntu 24.04 development image and the Dev Container maintainers'
Docker-in-Docker feature. It requests at least 2 CPU cores, 8 GB of memory and
32 GB of storage.

The feature reference is pinned to major version 4. Its `version` option is
separate and selects the Docker or Moby Engine installed inside the dev
container; `latest` keeps that engine on the feature's supported current
release.

Docker-in-Docker provides a dedicated Docker daemon inside the development
container. The learner node receives only the checked-out repository's public
`runtime`, `drills` and `checks` directories as read-only bind mounts. It does
not receive the repository root, Git metadata, local state, environment files,
a Docker socket, a home directory or SSH keys. Port 8100 is forwarded privately
and is accessible only to the signed-in codespace owner unless they deliberately
change its visibility.

The configuration does not build or start a lab automatically. Its
post-creation check only waits for Docker, validates the Compose model and runs
`./lab doctor`. This avoids an unexpected image download and leaves the choice
of distribution with the learner.

## Start a session

When the terminal reports that Codespaces is ready, run:

```bash
./lab up ubuntu
./lab break 01
./lab shell
```

Replace `ubuntu` with `debian` or `rocky` when you want another supported
distribution. Run `./lab down` before switching targets.

The service is forwarded on port 8100. In the browser editor, open the **Ports**
panel and select **Rescue web service**. The `127.0.0.1:8100` URL printed by the
lab refers to the codespace itself, not the learner's physical computer.

## Stop, resume and remove

Run `./lab down` when an exercise is finished. This removes the lab container
and network but preserves its small drill-state volume. Starting the same
distribution restores an active fault. Run `./lab reset` to remove the saved
state and return to a healthy server.

Stopping a codespace stops its compute use, but retained codespaces can still
consume storage allowance or incur storage charges. Closing a browser tab does
not necessarily stop the codespace. Stop it explicitly when pausing work and
delete it when it is no longer needed. Review [GitHub Codespaces billing](https://docs.github.com/en/billing/concepts/product-billing/github-codespaces)
before starting if the account has limited included usage.

Deleting the codespace removes its dedicated inner Docker images, volumes and
lab state. Commit and push any repository changes that must be kept before
deleting it.

## Security boundary

The Docker-in-Docker development container and the systemd lab container use
privileged operation. They are not security boundaries. Treat the codespace as
disposable, inspect the dev container and Compose configuration before use,
and do not run an untrusted fork.

The forwarded service port is private by default. Do not make it public for
this lab. No exercise requires incoming access from another user or service.
