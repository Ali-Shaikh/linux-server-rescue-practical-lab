#!/usr/bin/env python3
"""Verify that catalogue-declared companion images are multi-architecture."""

from __future__ import annotations

import csv
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "drills" / "catalog.tsv"
REQUIRED_PLATFORMS = {"linux/amd64", "linux/arm64"}


def fail(message: str) -> None:
    raise SystemExit(f"Companion platform check failed: {message}")


def run_json(command: list[str], description: str) -> dict[str, object]:
    try:
        completed = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or "command failed"
        fail(f"{description}: {detail}")

    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        fail(f"{description} returned invalid JSON: {error}")


inspected_images: set[str] = set()
with CATALOG.open(encoding="utf-8", newline="") as handle:
    drills = csv.DictReader(handle, delimiter="\t")
    for drill in drills:
        overlay = drill["overlay"]
        if overlay == "none":
            continue

        full_id = f"{drill['id']}-{drill['slug']}"
        overlay_path = ROOT / overlay
        if not overlay_path.is_file():
            fail(f"{full_id} is missing {overlay}")

        model = run_json(
            [
                "docker",
                "compose",
                "--project-name",
                "lsr",
                "--file",
                str(ROOT / "compose.yaml"),
                "--file",
                str(overlay_path),
                "config",
                "--format",
                "json",
            ],
            f"could not render {full_id}",
        )
        model_services = model.get("services")
        if not isinstance(model_services, dict):
            fail(f"{full_id} rendered model has no services object")

        for service_name in drill["services"].split(","):
            service = model_services.get(service_name)
            if not isinstance(service, dict):
                fail(f"{full_id} has no service named {service_name}")
            image = service.get("image")
            if not isinstance(image, str) or not image:
                fail(f"{full_id} service {service_name} has no image")
            if image in inspected_images:
                continue

            manifest = run_json(
                ["docker", "buildx", "imagetools", "inspect", "--raw", image],
                f"could not inspect {image}",
            )
            manifest_entries = manifest.get("manifests")
            if not isinstance(manifest_entries, list):
                fail(f"{image} does not publish a multi-platform image index")
            platforms = {
                f"{platform['os']}/{platform['architecture']}"
                for entry in manifest_entries
                if isinstance(entry, dict)
                and isinstance((platform := entry.get("platform")), dict)
                and platform.get("os")
                and platform.get("architecture")
            }
            missing = REQUIRED_PLATFORMS - platforms
            if missing:
                fail(f"{image} does not publish {', '.join(sorted(missing))}")

            inspected_images.add(image)
            print(f"PASS  {image} publishes amd64 and arm64 manifests.")

if not inspected_images:
    fail("the catalogue contains no scenario companion images")
