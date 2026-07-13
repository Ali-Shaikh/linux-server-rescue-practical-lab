# Linux Server Rescue Practical Lab

Diagnose and repair realistic Linux incidents on disposable servers you are
allowed to break.

> **Early build:** version 0.1.0-alpha.2 establishes the lab contract and ships one
> complete failed-service incident. The wider curriculum is planned in
> [`docs/CURRICULUM.md`](docs/CURRICULUM.md).

## What works today

- A selectable real systemd host called `relay`: Ubuntu, Debian or Rocky Linux.
- The same lifecycle commands in Bash and PowerShell.
- A complete service-failure drill with ordered hints, self-verification and a
  spoiler-fenced solution.
- Loopback-only access to the sample service at <http://127.0.0.1:8100>.
- Idempotent drill state that refuses to stack incidents.

## Quick start

You need Git, Docker Engine or Docker Desktop, Docker Compose 2.20 or later,
and about 3 GB of free disk space.

Choose one distribution at a time:

| Selector | Distribution | Package family | Notes |
|---|---|---|---|
| `ubuntu` | Ubuntu 26.04 LTS | `apt` | Default target |
| `debian` | Debian 13 | `apt` | Upstream Debian stable |
| `rocky` | Rocky Linux 10 | `dnf` | RHEL-compatible enterprise Linux |

The Rocky major-version image receives rolling updates and currently resolves
to Rocky Linux 10.2. Run `./lab distros` or `.\lab.ps1 distros` to see the
matrix without starting Docker.

### macOS and Linux

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

This lab does not mount the Docker socket, your home directory, your SSH keys,
or the host filesystem. It publishes its only port on `127.0.0.1`, labels its
resources `cloudsprocket.lab=rescue`, and its wrappers act only on the `lsr`
Compose project. Inspect [`compose.yaml`](compose.yaml) before running it, and
do not run an untrusted fork.

`down` keeps the small drill-state volume so a stopped session can resume.
`reset` removes that volume and returns the lab to a clean, healthy state.
Each distribution has a separate state volume. Run `down` before changing
targets, then start the next one with `up <distribution>`.

## Capability boundary

The current Docker backend teaches service, log, process, storage, permission,
network and DNS diagnosis across Debian-family and RHEL-compatible user spaces.
Containers share the Docker host's kernel, so `uname` reports that shared
kernel and the lab will not pretend to teach GRUB, initramfs, kernel selection,
physical disks or a real machine's boot path. Those topics require a later
VM-backed track.

Rocky Linux provides RHEL-compatible behaviour but does not include a Red Hat
subscription, Red Hat support or restricted RHEL content.

Once the image has been built, the lab and its exercises work offline.

## Licence and trademarks

The lab is free software under the [MIT licence](LICENSE).

Distribution and product names are used nominatively. This project is not
affiliated with or endorsed by Canonical, the Debian Project, the Rocky
Enterprise Software Foundation, Red Hat or Docker.
