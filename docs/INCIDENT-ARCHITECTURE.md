# Incident runtime architecture

## Decision

The Ubuntu, Debian and Rocky images are stable learner nodes. They contain the
operating system, systemd, common diagnostic tools, the `rescue` account and a
generic bootstrap only. Portable incident content is supplied from the checked
out repository at runtime through explicit read-only mounts.

Complex incidents may add a purpose-built companion service through a Compose
overlay. The learner still diagnoses and repairs the selected Linux node. The
companion represents a real external dependency such as an upstream API, DNS
server, database or certificate authority.

## Boundaries

| Incident type | Delivery | Test scope |
|---|---|---|
| Portable host fault | Mounted runtime and drill content | Ubuntu, Debian and Rocky |
| External dependency | Learner node plus a scenario Compose overlay | Every applicable learner distribution |
| Distribution-specific fault | Mounted content with an explicit distribution scope | Only the genuine platform family |
| Boot, kernel or block recovery | Future VM backend | VM acceptance matrix |

A companion is not created for a fault that belongs inside the learner node.
Permissions, local filesystems, systemd services, processes and listeners must
continue to use the selected learner distribution.

## Repository layout

- `docker/<distribution>/Dockerfile` builds a stable learner node.
- `docker/common/` contains only image-time bootstrap files.
- `runtime/` contains the healthy service baseline installed at container start.
- `drills/catalog.tsv` is the shared Bash and PowerShell drill catalogue.
- `drills/break`, `drills/checks`, `drills/fixtures` and `drills/restore` contain
  the incident lifecycle.
- `scenarios/<incident>/compose.yaml` may add an optional companion service.

Only `runtime/`, `drills/` and `checks/` are mounted into the learner node, and
they are read-only. The repository root, Git metadata, local state, agent files,
environment files, home directories, SSH material and the Docker socket are not
mounted. The root `.dockerignore` allow-lists only `docker/` for learner-image
builds so local internal files are not sent in the Docker build context.

## Lifecycle

The generic bootstrap performs these operations in order:

1. Install the healthy runtime baseline idempotently into the ephemeral node.
2. Read the active drill identifier from the labelled state volume.
3. Run the matching convention-based restore script when a drill is active.
4. Start systemd as PID 1.

The wrappers resolve drill aliases from the shared catalogue. A catalogue entry
may name a repository-relative Compose overlay. The wrapper accepts only an
overlay listed in the catalogue, remembers it under ignored `.local/` state,
and uses the same ordered Compose model for `up`, `down`, `reset`, `status` and
`logs`.

Compose overlays are selected with ordered `-f` arguments. This preserves the
documented Docker Compose 2.20.0 minimum. Compose `include` is not used because
it requires Docker Compose 2.20.3 or later.

## Acceptance rules

Every refactor must preserve the existing command contract and prove all
current incidents end to end on Ubuntu, Debian, Rocky and Codespaces. Each
incident must remain idempotent, survive container recreation, accept safe
repairs by outcome, and reset to a healthy baseline.

A companion service must be unprivileged, have no host port unless the exercise
requires one, mount no sensitive host path, expose a health check, and have
bounded resources. Its upstream image or toolchain is selected and pinned from
current authoritative documentation during implementation.
