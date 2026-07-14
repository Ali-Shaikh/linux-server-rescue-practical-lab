#!/usr/bin/env python3
"""Validate the usability evidence workflow contract."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "usability.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"Usability CI contract check failed: {message}")


text = WORKFLOW.read_text(encoding="utf-8")

for trigger in ("pull_request:", "push:", "workflow_dispatch:"):
    require(trigger in text, f"missing {trigger.removesuffix(':')} trigger")
require(
    re.search(r'(?m)^\s*tags:\s*\n\s*-\s*["\']v\*["\']\s*$', text) is not None,
    "version tags do not trigger usability evidence",
)
require("contents: read" in text, "workflow lacks read-only contents permission")
require("actions/upload-artifact@v7" in text, "workflow does not use current upload-artifact")
require("git clone --quiet" in text, "timing does not begin with a fresh clone")
require("--started-at" in text, "fresh clone is outside the measured interval")
require("tests/usability-evidence.py" in text, "evidence harness is not executed")
require("GITHUB_STEP_SUMMARY" in text, "job summary is not generated")
require("runner.temp" in text, "machine-readable evidence is not kept in runner storage")
require("retention-days: 30" in text, "evidence retention is not bounded")
require("if: always()" in text, "failed evidence is not retained for diagnosis")
require(
    "if: github.event_name != 'pull_request' || "
    "github.event.pull_request.head.repo.full_name == github.repository" in text,
    "fork pull requests can execute the Docker evidence job",
)
require(
    "SOURCE_REPOSITORY: ${{ github.repository }}" in text,
    "workflow can clone a contributor-controlled fork",
)
require(
    re.search(
        r"(?mi)^(?!\s*#)(?:.*\$\{\{[^}\n]*\bsecrets(?:\.|\[)|\s*secrets\s*:)",
        text,
    )
    is None,
    "workflow consumes repository secrets",
)
require(
    re.search(
        r"(?mi)^\s*(?:permissions\s*:\s*write-all|[a-z-]+\s*:\s*write)\s*$",
        text,
    )
    is None,
    "workflow declares write permission",
)

print("Usability CI configuration check passed.")
