#!/usr/bin/env python3
"""Measure the automated fresh-clone path and peak lab-container memory."""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import subprocess
import threading
import time
from datetime import UTC, datetime
from pathlib import Path


TIME_LIMIT_SECONDS = 10 * 60
MEMORY_LIMIT_BYTES = 4 * 1024**3
MEMORY_PATTERN = re.compile(r"^([0-9]+(?:\.[0-9]+)?)\s*([kmgtpe]?i?b)$", re.IGNORECASE)
MEMORY_MULTIPLIERS = {
    "b": 1,
    "kb": 1000,
    "mb": 1000**2,
    "gb": 1000**3,
    "tb": 1000**4,
    "pb": 1000**5,
    "eb": 1000**6,
    "kib": 1024,
    "mib": 1024**2,
    "gib": 1024**3,
    "tib": 1024**4,
    "pib": 1024**5,
    "eib": 1024**6,
}


def parse_memory(value: str) -> int:
    """Convert a Docker memory value such as 12.5MiB to bytes."""
    match = MEMORY_PATTERN.fullmatch(value.strip())
    if not match:
        raise ValueError(f"Unsupported Docker memory value: {value!r}")
    number, unit = match.groups()
    return round(float(number) * MEMORY_MULTIPLIERS[unit.lower()])


def within_time_limit(elapsed_seconds: float) -> bool:
    return elapsed_seconds <= TIME_LIMIT_SECONDS


def within_memory_limit(peak_bytes: int) -> bool:
    return peak_bytes <= MEMORY_LIMIT_BYTES


def command_text(command: list[str]) -> str:
    return " ".join(command)


def run(
    command: list[str],
    *,
    root: Path,
    check: bool = True,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    print(f"$ {command_text(command)}", flush=True)
    return subprocess.run(
        command,
        cwd=root,
        check=check,
        capture_output=capture_output,
        text=True,
    )


def command_output(command: list[str], *, root: Path) -> str:
    return run(command, root=root, capture_output=True).stdout.strip()


def list_lsr_resources(root: Path) -> dict[str, list[str]]:
    commands = {
        "containers": ["docker", "ps", "--all", "--format", "{{.Names}}"],
        "volumes": ["docker", "volume", "ls", "--format", "{{.Name}}"],
        "networks": ["docker", "network", "ls", "--format", "{{.Name}}"],
    }
    resources: dict[str, list[str]] = {}
    for resource_type, command in commands.items():
        names = command_output(command, root=root).splitlines()
        resources[resource_type] = sorted(
            name for name in names if name == "lsr" or name.startswith("lsr-")
        )
    return resources


def claim_clean_lsr_project(root: Path) -> None:
    resources = list_lsr_resources(root)
    occupied = [
        f"{resource_type}: {', '.join(names)}"
        for resource_type, names in resources.items()
        if names
    ]
    if occupied:
        raise RuntimeError(
            "Refusing to run because existing lsr resources are not owned by this "
            f"measurement: {'; '.join(occupied)}"
        )


class DockerStatsSampler:
    """Sample total memory for running containers owned by this lab."""

    def __init__(self, root: Path, interval_seconds: float = 1.0) -> None:
        self.root = root
        self.interval_seconds = interval_seconds
        self.peak_total_bytes = 0
        self.per_container_peak_bytes: dict[str, int] = {}
        self.sample_count = 0
        self.errors: list[str] = []
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._sample_loop, daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=10)
        if self._thread.is_alive():
            self.errors.append("Docker stats sampler did not stop within 10 seconds")

    def _running_lab_containers(self) -> list[str]:
        completed = subprocess.run(
            [
                "docker",
                "ps",
                "--filter",
                "label=cloudsprocket.lab=rescue",
                "--format",
                "{{.Names}}",
            ],
            cwd=self.root,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            self.errors.append(completed.stderr.strip() or "docker ps failed")
            return []
        return [line for line in completed.stdout.splitlines() if line]

    def _sample(self) -> None:
        containers = self._running_lab_containers()
        if not containers:
            return

        completed = subprocess.run(
            [
                "docker",
                "stats",
                "--no-stream",
                "--format",
                "{{json .}}",
                *containers,
            ],
            cwd=self.root,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            # Containers can disappear between docker ps and docker stats during reset.
            return

        sample_total = 0
        sampled = False
        for line in completed.stdout.splitlines():
            if not line:
                continue
            try:
                row = json.loads(line)
                name = str(row["Name"])
                usage = str(row["MemUsage"]).split("/", maxsplit=1)[0].strip()
                usage_bytes = parse_memory(usage)
            except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
                self.errors.append(f"Could not parse docker stats row {line!r}: {error}")
                continue

            sampled = True
            sample_total += usage_bytes
            self.per_container_peak_bytes[name] = max(
                usage_bytes,
                self.per_container_peak_bytes.get(name, 0),
            )

        if sampled:
            self.sample_count += 1
            self.peak_total_bytes = max(self.peak_total_bytes, sample_total)

    def _sample_loop(self) -> None:
        while not self._stop.is_set():
            try:
                self._sample()
            except OSError as error:
                self.errors.append(f"Docker stats sampler failed: {error}")
                self._stop.set()
            self._stop.wait(self.interval_seconds)


def collect_runner_context(root: Path) -> dict[str, str]:
    return {
        "operating_system": platform.platform(),
        "machine": platform.machine(),
        "docker_server": command_output(
            ["docker", "version", "--format", "{{.Server.Version}}"], root=root
        ),
        "docker_compose": command_output(
            ["docker", "compose", "version", "--short"], root=root
        ),
        "commit": command_output(["git", "rev-parse", "HEAD"], root=root),
    }


def run_quick_start(root: Path, started_at: float) -> dict[str, object]:
    run(["bash", "./lab", "doctor", "ubuntu"], root=root)
    run(["bash", "./lab", "up", "ubuntu"], root=root)
    run(["bash", "./lab", "break", "01"], root=root)
    run(
        [
            "docker",
            "exec",
            "--user",
            "rescue",
            "--workdir",
            "/home/rescue",
            "lsr-relay",
            "sh",
            "-c",
            "test \"$(id -u)\" -ne 0 && test -r /opt/lab/drills/01-service-failure.md",
        ],
        root=root,
    )
    run(
        [
            "docker",
            "exec",
            "lsr-relay",
            "sh",
            "-c",
            "test \"$(cat /var/lib/cloudsprocket-lab/active-drill)\" = 01-service-failure",
        ],
        root=root,
    )

    elapsed_seconds = round(time.time() - started_at, 2)
    return {
        "definition": (
            "Fresh git clone through doctor, Ubuntu startup, incident 01 activation "
            "and a non-interactive learner-shell readiness probe"
        ),
        "distribution": "ubuntu",
        "elapsed_seconds": elapsed_seconds,
        "limit_seconds": TIME_LIMIT_SECONDS,
        "passed": within_time_limit(elapsed_seconds),
        "interactive_substitution": (
            "The interactive ./lab shell command is replaced by the same non-root "
            "container entry and drill-readability checks."
        ),
    }


def run_resource_suite(root: Path) -> tuple[dict[str, object], int]:
    sampler = DockerStatsSampler(root)
    sampler.start()
    try:
        completed = run(
            ["bash", "./tests/smoke.sh", "ubuntu"],
            root=root,
            check=False,
        )
    finally:
        sampler.stop()

    peak_mib = round(sampler.peak_total_bytes / 1024**2, 2)
    return (
        {
            "definition": (
                "Peak summed memory reported by docker stats for running "
                "cloudsprocket.lab=rescue containers during the complete Ubuntu incident suite"
            ),
            "peak_total_bytes": sampler.peak_total_bytes,
            "peak_total_mib": peak_mib,
            "limit_bytes": MEMORY_LIMIT_BYTES,
            "limit_mib": MEMORY_LIMIT_BYTES // 1024**2,
            "samples": sampler.sample_count,
            "per_container_peak_bytes": dict(sorted(sampler.per_container_peak_bytes.items())),
            "sampler_errors": sampler.errors,
            "suite_exit_code": completed.returncode,
            "passed": (
                completed.returncode == 0
                and sampler.sample_count > 0
                and not sampler.errors
                and within_memory_limit(sampler.peak_total_bytes)
            ),
        },
        completed.returncode,
    )


def render_summary(report: dict[str, object]) -> str:
    quick_start = report.get("quick_start", {})
    resources = report.get("resources", {})
    status = "PASS" if report.get("passed") else "FAIL"
    return "\n".join(
        [
            "## Linux Server Rescue usability evidence",
            "",
            f"Overall: **{status}**",
            "",
            "| Gate | Result | Limit | Status |",
            "|---|---:|---:|---|",
            (
                f"| Fresh-clone command path | {quick_start.get('elapsed_seconds', 'n/a')} s "
                f"| {quick_start.get('limit_seconds', TIME_LIMIT_SECONDS)} s "
                f"| {'PASS' if quick_start.get('passed') else 'FAIL'} |"
            ),
            (
                f"| Peak lab-container memory | {resources.get('peak_total_mib', 'n/a')} MiB "
                f"| {resources.get('limit_mib', MEMORY_LIMIT_BYTES // 1024**2)} MiB "
                f"| {'PASS' if resources.get('passed') else 'FAIL'} |"
            ),
            "",
            "The timing includes a fresh Git clone. The interactive shell is checked with a "
            "non-interactive equivalent. Codespaces click-to-success timing and human "
            "documentation judgement remain manual evidence.",
            "",
        ]
    )


def write_report(path: Path, report: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def cleanup(root: Path) -> None:
    try:
        subprocess.run(
            [
                "docker",
                "compose",
                "--project-name",
                "lsr",
                "--file",
                "compose.yaml",
                "--file",
                "scenarios/08-upstream-port/compose.yaml",
                "down",
                "--volumes",
                "--remove-orphans",
            ],
            cwd=root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--started-at", type=float, default=time.time())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    report: dict[str, object] = {
        "schema_version": 1,
        "measured_at": datetime.now(UTC).isoformat(),
        "source": "automated-github-runner",
        "manual_evidence": {
            "codespaces_click_to_success": "not measured by this workflow",
            "human_walkthrough_judgement": "not measured by this workflow",
        },
    }
    errors: list[str] = []
    owns_lsr_project = False

    try:
        report["runner"] = collect_runner_context(root)
        claim_clean_lsr_project(root)
        owns_lsr_project = True
        report["quick_start"] = run_quick_start(root, args.started_at)
        resources, suite_exit_code = run_resource_suite(root)
        report["resources"] = resources
        if suite_exit_code != 0:
            errors.append(f"Ubuntu incident suite exited with {suite_exit_code}")
        if not report["quick_start"]["passed"]:
            errors.append("Fresh-clone command path exceeded 600 seconds")
        if not resources["passed"]:
            errors.append("Resource evidence did not satisfy the 4 GiB contract")
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        errors.append(str(error))
    finally:
        if owns_lsr_project:
            cleanup(root)

    report["errors"] = errors
    report["passed"] = not errors
    write_report(args.output, report)
    summary = render_summary(report)
    print(summary)
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as handle:
            handle.write(summary)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
