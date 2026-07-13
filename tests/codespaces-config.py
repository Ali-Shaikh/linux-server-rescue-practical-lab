#!/usr/bin/env python3
"""Validate the repository's learner-facing Codespaces contract."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / ".devcontainer" / "devcontainer.json"
README_PATH = ROOT / "README.md"
FEATURE = "ghcr.io/devcontainers/features/docker-in-docker:4"
LAUNCH_URL = (
    "https://codespaces.new/Ali-Shaikh/"
    "linux-server-rescue-practical-lab?quickstart=1"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"Codespaces configuration check failed: {message}")


config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
readme = README_PATH.read_text(encoding="utf-8")
feature = config.get("features", {}).get(FEATURE, {})
resources = {"cpus": 2, "memory": "8gb", "storage": "32gb"}
port = config.get("portsAttributes", {}).get("8100", {})

require(
    config.get("image") == "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
    "unexpected base image",
)
require(feature, "current Docker-in-Docker feature is missing")
require(feature.get("dockerDashComposeVersion") == "v2", "Compose v2 is not requested")
require(config.get("hostRequirements") == resources, "resource floor changed")
require(config.get("forwardPorts") == [8100], "only port 8100 should be forwarded")
require(port.get("onAutoForward") == "silent", "port 8100 should not open automatically")
require(
    config.get("postCreateCommand") == "bash .devcontainer/post-create.sh",
    "post-create validation is not configured",
)
require("mounts" not in config, "the repository must not add host mounts")
require(
    "privileged" not in config,
    "privilege must come only from the reviewed Docker-in-Docker feature",
)
require(LAUNCH_URL in readme, "README launch link is missing or points elsewhere")
require(
    "https://github.com/codespaces/badge.svg" in readme,
    "official Codespaces badge is missing",
)

print("Codespaces configuration check passed.")
