# Release evidence

The automated usability gate records two reproducible measurements for the
Linux Server Rescue lab. It complements, but does not replace, a human
fresh-learner walkthrough.

## Automated measurements

The `Usability evidence` workflow starts its clock before cloning the reviewed
revision into a clean GitHub-hosted runner. It follows the documented Ubuntu
quick-start command path through `doctor`, `up` and `break 01`, then replaces
the interactive `lab shell` with an equivalent non-root shell-readiness probe.
The incident must be active and the learner must be able to read its brief.
The complete path must finish within 600 seconds.

After the quick-start image is warm, the workflow runs the complete Ubuntu
incident suite. It samples `docker stats` approximately once per second and
sums memory only for running containers carrying the
`cloudsprocket.lab=rescue` label. The observed peak must remain at or below
4 GiB. The workflow uploads the JSON report for 30 days and writes the two
results to the GitHub Actions job summary.

The workflow is read-only. It receives no repository secrets, publishes no
images and keeps generated evidence in runner storage rather than the source
tree. Pull requests from forks do not run the Docker evidence job; a maintainer
must place the revision on a trusted repository branch or run the gate after
merge. Before creating anything, the harness also refuses to run when an
existing container, volume or network uses the `lsr` project prefix. Cleanup is
enabled only after that ownership check succeeds.

## Evidence boundary

Automation can prove that the documented command path works from a clean clone,
that the first incident is ready and that the runtime remains within its
container-memory budget. It cannot judge whether instructions are clear to a
new learner, measure attention from clicking the Codespaces badge, or assess an
interactive shell experience.

Ali's manual fresh-learner walkthrough and Codespaces click-to-success timing
are waived for the current alpha iteration. They remain explicit manual gates
before the stable `v0.1.0` release.

## Reviewed runs

Recorded measurements are added here only after a workflow run has completed on
the exact reviewed commit.

| Measured at | Commit and run | Fresh-clone path | Peak memory | Samples | Result |
|---|---|---:|---:|---:|---|
| 2026-07-14 20:06 UTC | [`8e46d4b`](https://github.com/Ali-Shaikh/linux-server-rescue-practical-lab/commit/8e46d4bf0a41e66c0e55ccb482f55a03340d15ba), [run 29364393631](https://github.com/Ali-Shaikh/linux-server-rescue-practical-lab/actions/runs/29364393631) | 27.12 s / 600 s | 35.41 MiB / 4096 MiB | 61 | PASS |

The reviewed run used an x86_64 GitHub-hosted runner with Docker Engine 28.0.4
and Docker Compose 2.38.2. The complete Ubuntu incident suite exited 0, the
sampler reported no errors, and the retained JSON artefact was named
`usability-evidence-29364393631-1`.
