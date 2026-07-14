#!/usr/bin/env python3
"""Validate the public incident runtime and image-boundary contracts."""

from __future__ import annotations

import csv
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "drills" / "catalog.tsv"
EXPECTED_FIELDS = ["id", "slug", "difficulty", "scope", "overlay", "description"]
GENERIC_IMAGE_FILES = {"configure-image.sh", "init-lab"}
RUNTIME_FILES = {
    "install.sh",
    "rescue-cpu-hog",
    "rescue-cpu-hog.service",
    "rescue-data-volume.service",
    "rescue-upstream-check",
    "rescue-upstream-check.service",
    "rescue-web-config.json",
    "rescue-web.py",
    "rescue-web.service",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"Repository contract check failed: {message}")


with CATALOG.open(encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    require(reader.fieldnames == EXPECTED_FIELDS, "unexpected drill catalogue fields")
    drills = list(reader)

require(drills, "drill catalogue is empty")
require(
    {path.name for path in (ROOT / "docker" / "common").iterdir() if path.is_file()}
    == GENERIC_IMAGE_FILES,
    "docker/common must contain only generic image bootstrap files",
)
require(
    {path.name for path in (ROOT / "runtime").iterdir() if path.is_file()}
    == RUNTIME_FILES,
    "runtime file set is incomplete or unexpected",
)

seen_slugs: set[str] = set()
for index, drill in enumerate(drills, start=1):
    drill_id = drill["id"]
    slug = drill["slug"]
    full_id = f"{drill_id}-{slug}"
    overlay = drill["overlay"]

    require(drill_id == f"{index:02d}", f"{full_id} is not sequential")
    require(bool(re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", slug)), f"bad slug {slug}")
    require(slug not in seen_slugs, f"duplicate slug {slug}")
    seen_slugs.add(slug)
    require(drill["difficulty"] in {"Beginner", "Intermediate", "Advanced"}, f"bad difficulty for {full_id}")
    require(
        drill["scope"] in {"portable", "ubuntu", "debian", "rocky", "debian-family", "rhel-family"},
        f"bad scope for {full_id}",
    )
    require(bool(drill["description"].strip()), f"missing description for {full_id}")

    required_paths = [
        ROOT / "drills" / f"{full_id}.md",
        ROOT / "drills" / "break" / f"{full_id}.sh",
        ROOT / "drills" / "checks" / f"{full_id}.sh",
        ROOT / "drills" / "restore" / f"{full_id}.sh",
        ROOT / "drills" / "solutions" / f"{full_id}.md",
    ]
    for path in required_paths:
        require(path.is_file(), f"{full_id} is missing {path.relative_to(ROOT)}")

    if overlay != "none":
        require(
            bool(re.fullmatch(r"scenarios/[a-z0-9][a-z0-9-]*/compose\.yaml", overlay))
            and ".." not in overlay,
            f"unsafe overlay for {full_id}",
        )
        require((ROOT / overlay).is_file(), f"missing overlay for {full_id}")

dockerignore = [
    line
    for line in (ROOT / ".dockerignore").read_text(encoding="utf-8").splitlines()
    if line and not line.startswith("#")
]
require(
    dockerignore == ["**", "!docker/", "!docker/**"],
    "learner-image build context must allow-list only docker/",
)

for distro in ("ubuntu", "debian", "rocky"):
    dockerfile = (ROOT / "docker" / distro / "Dockerfile").read_text(encoding="utf-8")
    for forbidden in ("COPY runtime", "COPY drills", "COPY checks", "rescue-web.py"):
        require(forbidden not in dockerfile, f"{distro} image embeds incident runtime content")

model = json.loads(
    subprocess.run(
        [
            "docker",
            "compose",
            "--project-name",
            "lsr",
            "--file",
            str(ROOT / "compose.yaml"),
            "config",
            "--format",
            "json",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
)
relay = model["services"]["relay"]
binds = {
    volume["target"]: volume
    for volume in relay.get("volumes", [])
    if volume.get("type") == "bind"
}
expected_binds = {
    "/opt/lab/runtime": "runtime",
    "/opt/lab/drills": "drills",
    "/opt/lab/checks": "checks",
}
require(set(binds) == set(expected_binds), "learner node has unexpected bind mounts")
for target, source_name in expected_binds.items():
    volume = binds[target]
    require(volume.get("read_only") is True, f"{target} is not read-only")
    require(Path(volume["source"]).name == source_name, f"{target} has the wrong source")

print("Repository contract check passed.")
