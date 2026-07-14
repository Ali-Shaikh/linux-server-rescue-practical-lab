# Scenario overlays

This directory is reserved for incidents that require a genuine external
dependency. Each scenario owns a directory containing `compose.yaml` and the
smallest possible companion-service build context.

The drill catalogue must name the overlay as
`scenarios/<incident>/compose.yaml`. The wrappers reject overlays that are not
listed in the catalogue or do not match that repository-relative path shape.

Companion services must be unprivileged, internally reachable only unless a
learner-facing port is essential, health-checked, resource-bounded and free of
sensitive host mounts. A companion supports the incident but does not replace
the selected Ubuntu, Debian or Rocky learner node.
