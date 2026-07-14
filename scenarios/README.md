# Scenario overlays

This directory is reserved for incidents that require a genuine external
dependency. Each scenario owns a directory containing `compose.yaml` and only
the smallest required public companion content or build context.

The drill catalogue must name the overlay as
`scenarios/<incident>/compose.yaml` and list its companion service names. The
wrappers reject overlays and service names that are not in that catalogue.

Companion services must be unprivileged, internally reachable only unless a
learner-facing port is essential, health-checked, resource-bounded and free of
sensitive host mounts. A companion supports the incident but does not replace
the selected Ubuntu, Debian or Rocky learner node.
