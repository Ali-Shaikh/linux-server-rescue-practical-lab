# Linux Server Rescue Practical Lab

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/Ali-Shaikh/linux-server-rescue-practical-lab?quickstart=1)

Diagnose and repair realistic Linux incidents on disposable servers you are
allowed to break.

> **Early build:** version 0.1.0-alpha.8 establishes the lab contract and ships ten
> complete rescue incidents. The wider curriculum is planned in
> [`docs/CURRICULUM.md`](docs/CURRICULUM.md).

## What works today

- A selectable real systemd host called `relay`: Ubuntu, Debian or Rocky Linux.
- The same lifecycle commands in Bash and PowerShell.
- Ten complete drills spanning services, storage, permissions, DNS, process
  load, networking and change recovery, each with ordered hints,
  self-verification and a spoiler-fenced solution.
- Loopback-only access to the sample service at <http://127.0.0.1:8100>.
- Idempotent drill state that refuses to stack incidents.
- Stable learner-node images with public incident content mounted read-only from
  the checked-out repository.
- A one-click Codespaces environment with a dedicated Docker daemon.
- Dedicated build validation for every learner image on amd64 and arm64.

## Quick start

Choose one distribution at a time:

| Selector | Distribution | Package family | Notes |
|---|---|---|---|
| `ubuntu` | Ubuntu 26.04 LTS | `apt` | Default target |
| `debian` | Debian 13 | `apt` | Upstream Debian stable |
| `rocky` | Rocky Linux 10 | `dnf` | RHEL-compatible enterprise Linux |

The Rocky major-version image receives rolling updates and currently resolves
to Rocky Linux 10.2. Run `./lab distros` or `.\lab.ps1 distros` to see the
matrix without starting Docker.

### GitHub Codespaces

Select the **Open in GitHub Codespaces** badge above. The configuration requests
at least 2 CPU cores, 8 GB of memory and 32 GB of storage. It creates a
dedicated Docker-in-Docker daemon, keeps forwarded port 8100 private, and does
not start or download a lab image until you choose a distribution.

When the terminal is ready:

```bash
./lab up ubuntu
./lab break 01
./lab shell
```

In the browser editor, open **Ports** and select **Rescue web service** to reach
the forwarded application. Codespaces can consume included usage or incur
compute and storage charges. Stop it when pausing and delete it when finished.
See the [Codespaces guide](docs/CODESPACES.md) for lifecycle, cost and security
details.

### macOS and Linux

You need Git, Docker Engine or Docker Desktop, Docker Compose 2.20 or later,
and about 3 GB of free disk space.

```bash
git clone https://github.com/Ali-Shaikh/linux-server-rescue-practical-lab.git
cd linux-server-rescue-practical-lab
./lab doctor
./lab up debian
./lab break 01
./lab shell
```

### Windows PowerShell

```powershell
git clone https://github.com/Ali-Shaikh/linux-server-rescue-practical-lab.git
Set-Location linux-server-rescue-practical-lab
.\lab.ps1 doctor
.\lab.ps1 up rocky
.\lab.ps1 break 01
.\lab.ps1 shell
```

Open [`drills/01-service-failure.md`](drills/01-service-failure.md) for the
incident ticket. When you believe the server is repaired, leave the shell and
run `./lab verify 01` or `.\lab.ps1 verify 01`.

## Available incidents

| Number | Incident | Capability |
|---|---|---|
| `01` | [Service failure](drills/01-service-failure.md) | Diagnose a systemd service trapped in a restart loop. |
| `02` | [Full filesystem](drills/02-full-filesystem.md) | Find and recover the application filesystem that has no free space. |
| `03` | [DNS ghost](drills/03-dns-ghost.md) | Find local name-service configuration shadowing the expected DNS answer. |
| `04` | [Permission denied](drills/04-permission-denied.md) | Repair least-privilege access to application data. |
| `05` | [Runaway process](drills/05-runaway-process.md) | Trace and stop a restart-managed CPU worker. |
| `06` | [Invalid configuration](drills/06-invalid-configuration.md) | Validate and safely roll back malformed JSON. |
| `07` | [Wrong listener](drills/07-wrong-listener.md) | Repair a service bound only to container loopback. |
| `08` | [Upstream port](drills/08-upstream-port.md) | Restore a systemd probe using the wrong external upstream port. |
| `09` | [Port conflict](drills/09-port-conflict.md) | Find and remove an unauthorised service occupying the application port. |
| `10` | [Scheduled regression](drills/10-scheduled-regression.md) | Stop recurring automation from restoring a bad application port. |

## Command contract

| Command | Purpose |
|---|---|
| `up [distribution]` | Build and start Ubuntu, Debian or Rocky Linux. |
| `down` | Stop and remove only this lab's containers and network. |
| `reset` | Remove containers, the lab network and lab volumes, then rebuild a healthy lab. |
| `status` | Show container health, the service URL and the active drill. |
| `doctor` | Check Docker, Compose, disk space, port 8100 and stale state. |
| `check <exercise>` | Run an exercise check when exercises are added. |
| `break <drill>` | Apply an incident without stacking a second drill. |
| `verify <drill>` | Inspect the repair without changing drill state. |
| `drills` | List the available incidents. |
| `distros` | List the supported distribution targets. |
| `shell` | Open a shell as the `rescue` user. |
| `logs` | Follow the lab container logs. |
| `version` | Print the lab version. |

## Safety and trust boundary

The host uses real systemd, which requires `privileged: true` and the host
cgroup namespace in Docker Compose. Docker documents that a privileged
container is not a security boundary and can potentially affect its host.

The learner node bind-mounts only this repository's public `runtime`, `drills`
and `checks` directories, all read-only. It does not mount the repository root,
Git metadata, `.local` state, environment files, the Docker socket, your home
directory or your SSH keys. The learner-image build context allow-lists only
`docker/`, so local internal files are not sent to that build. The lab publishes
its only port on `127.0.0.1`, labels its resources
`cloudsprocket.lab=rescue`, and its wrappers act only on the `lsr` Compose
project. Inspect [`compose.yaml`](compose.yaml) and the
[incident architecture](docs/INCIDENT-ARCHITECTURE.md) before running it, and do
not run an untrusted fork.

Codespaces uses a privileged Docker-in-Docker development container and then
runs the same privileged systemd lab inside its dedicated daemon. It does not
mount an external Docker socket. The codespace is still disposable rather than
a security boundary; inspect [its configuration](.devcontainer/devcontainer.json)
before launching an untrusted branch.

`down` keeps the small drill-state volume so a stopped session can resume.
The saved fault is restored when that distribution starts again. `reset`
removes the state volume and returns the lab to a clean, healthy state.
Each distribution has a separate state volume. Run `down` before changing
targets, then start the next one with `up <distribution>`.

Incident 02 mounts a size-limited 16 MiB tmpfs inside the container. It does
not fill or mount the host filesystem. The tmpfs uses at most 16 MiB of the
Docker host's memory or swap and disappears with the container.

Incident 05 runs one deliberately busy worker under a systemd `CPUQuota` of
20% of one CPU, a 32 MiB memory limit and a low scheduling priority. The worker
exists only inside the disposable lab container and is removed by `lab reset`.

Incident 08 adds a purpose-built BusyBox companion on the internal Compose
network. It runs as an unprivileged user with all Linux capabilities dropped, a
read-only root filesystem, no host port, a health check and explicit CPU,
memory and process limits. A failed break removes the uncommitted companion;
`down` and `up` preserve a committed incident, while `reset` removes it.

Incident 09 starts a Python standard-library debug listener as the unprivileged
`rescue` user inside the disposable learner node. It uses only the existing
container port, adds no host exposure and is removed with the learner container
by `lab reset`.

Incident 10 runs a bounded systemd timer inside the disposable learner node.
It changes only the lab application's runtime state, contacts no external
service and is removed with the learner container by `lab reset`.

## Capability boundary

The current Docker backend teaches service, log, process, storage, permission,
network and DNS diagnosis across Debian-family and RHEL-compatible user spaces.
Containers share the Docker host's kernel, so `uname` reports that shared
kernel and the lab will not pretend to teach GRUB, initramfs, kernel selection,
physical disks or a real machine's boot path. Those topics require a later
VM-backed track.

Rocky Linux provides RHEL-compatible behaviour but does not include a Red Hat
subscription, Red Hat support or restricted RHEL content.

Once the learner and pinned companion images have been downloaded or built,
the checked-out lab and its exercises work offline.

## Release validation

The `Release image validation` workflow builds the Ubuntu, Debian and Rocky
learner images separately for `linux/amd64` and `linux/arm64`. It also verifies
that every catalogue-declared companion image publishes both architectures.
The workflow runs for relevant pull requests and `main` changes, every `v*`
tag, and manual dispatches. It validates builds but does not publish images.

The complete incident runtime suite continues to run natively on amd64 across
Ubuntu, Debian, Rocky and Codespaces. Multi-architecture runtime smoke remains
separate from this build-compatibility gate.

The separate `Usability evidence` workflow measures the fresh-clone Ubuntu
command path and samples peak container memory throughout the complete Ubuntu
incident suite. See the [release evidence contract](docs/RELEASE-EVIDENCE.md)
for thresholds, generated artefacts and the manual evidence boundary.

## Licence and trademarks

The lab is free software under the [MIT licence](LICENSE).

Distribution and product names are used nominatively. This project is not
affiliated with or endorsed by Canonical, the Debian Project, the Rocky
Enterprise Software Foundation, Red Hat or Docker.
