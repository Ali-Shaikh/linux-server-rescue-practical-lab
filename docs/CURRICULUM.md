# Linux Server Rescue curriculum

Status: first three vertical slices in build, 2026-07-13.

## Learning promise

A learner receives an incident ticket, enters a real Linux environment,
collects evidence, makes the smallest safe repair, and proves the service is
healthy. The lab marks outcomes without revealing the answer.

The path assumes basic terminal familiarity but does not assume professional
operations experience. It comes before the Docker lab because it teaches the
host-level evidence and failure modes that container debugging builds upon.

## Distribution matrix

Every core incident must pass unchanged on Ubuntu 26.04 LTS, Debian 13 and
Rocky Linux 10. This covers upstream Debian, Ubuntu and a RHEL-compatible
enterprise user space without requiring three hosts to run at once.

Generic incidents assess outcomes rather than a distribution-specific command.
Where package management, file locations or security defaults differ, the
brief identifies the family and teaches both `apt` and `dnf` paths explicitly.
The matrix is representative, not exhaustive. An openSUSE or SLES-family target
is a candidate after the first release once it meets the same systemd, amd64,
arm64 and resource acceptance checks.

## Delivery order

Stage numbers describe the capability progression, while incident numbers
describe implementation and release order. They are intentionally independent,
so an incident may implement a later curriculum stage first.

| Stage | Capability | Candidate incidents | Backend | Status |
|---|---|---|---|---|
| 1 | Services and logs | Bad systemd override, restart loop, stale dependency | Docker | First incident implemented |
| 2 | Capacity | Full filesystem, deleted-open file, exhausted inodes | Docker | Full-filesystem incident implemented |
| 3 | Identity and access | Wrong ownership, broken sudo rule, locked service account | Docker | Planned |
| 4 | Networking and DNS | Wrong listener, bad resolver, shadowed hosts entry | Docker | DNS shadow incident implemented |
| 5 | Processes and performance | Runaway process, memory pressure, file descriptor exhaustion | Docker | Planned |
| 6 | Change recovery | Invalid configuration, failed package transition, unsafe rollback | Docker | Planned |
| 7 | Boot and block storage | Broken fstab, initramfs, bootloader and filesystem recovery | VM | Later track |

## Incident design rules

Every incident must:

1. Start from a healthy, observable baseline.
2. Have one primary fault and no hidden second answer.
3. Be diagnosable from evidence available inside the host.
4. Accept more than one safe repair where the real system would.
5. Verify the service outcome, not a memorised command or exact file content.
6. Include three ordered hints and a spoiler-fenced solution.
7. Reset cleanly and remain usable after Docker or Codespaces restarts.

## First release target

Version 0.1 should contain three complete incidents:

- `01-service-failure`: a bad systemd override causes a restart loop.
- `02-full-filesystem`: application writes fail while misleading free-space
  symptoms force the learner to inspect the correct filesystem.
- `03-dns-ghost`: name resolution fails because local configuration shadows
  the expected DNS answer.

Release acceptance requires both wrappers, the full incident loop on every
supported distribution, amd64 and arm64 image builds, restart resilience, and
a 2-core and 8 GB resource run. The honest Codespaces quick start is now
implemented and remains part of the release regression suite.

## Deliberate exclusions

The Docker backend shares its host kernel. It cannot faithfully reproduce a
real bootloader, initramfs, kernel upgrade, hardware fault, physical block
device or offline filesystem repair. These are not represented by fake
commands or scripted terminal output. A VM backend must pass a separate
resource and portability review before those incidents are promised.
