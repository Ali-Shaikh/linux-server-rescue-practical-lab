#!/usr/bin/env python3
"""Validate the multi-architecture release workflow contract."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "release-images.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"Release CI contract check failed: {message}")


text = WORKFLOW.read_text(encoding="utf-8")

for trigger in ("pull_request:", "push:", "workflow_dispatch:"):
    require(trigger in text, f"missing {trigger.removesuffix(':')} trigger")
require(
    re.search(r'(?m)^\s*tags:\s*\n\s*-\s*["\']v\*["\']\s*$', text) is not None,
    "version tags do not trigger release validation",
)

for action in (
    "actions/checkout@v6",
    "docker/setup-qemu-action@v4",
    "docker/setup-buildx-action@v4",
    "docker/build-push-action@v7",
):
    require(action in text, f"missing current action {action}")

matrix_rows = set(
    re.findall(
        r"- distro: (ubuntu|debian|rocky)\n"
        r"\s+platform: (linux/(?:amd64|arm64))\n"
        r"\s+arch: (amd64|arm64)",
        text,
    )
)
expected_rows = {
    (distro, f"linux/{arch}", arch)
    for distro in ("ubuntu", "debian", "rocky")
    for arch in ("amd64", "arm64")
}
require(matrix_rows == expected_rows, "learner image matrix is not the required 3 by 2 set")

require("platforms: ${{ matrix.platform }}" in text, "Buildx does not use the matrix platform")
require("pull: true" in text, "validation does not refresh upstream base images")
require("push: false" in text, "validation must not publish learner images")
require("push: true" not in text, "validation unexpectedly publishes learner images")
require("outputs: type=cacheonly" in text, "validation build output is not cache-only")
require("python3 tests/companion-platforms.py" in text, "companion manifest validation is missing")
require("contents: read" in text, "workflow permissions are broader than read-only contents")
require(
    re.search(r"(?mi)^(?!\s*#).*\$\{\{\s*secrets\.", text) is None,
    "validation must not consume repository secrets",
)

print("Release CI configuration check passed.")
