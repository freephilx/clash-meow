#!/usr/bin/env python3
"""Prepare and stage checksum-locked Mihomo runtime resources."""

from __future__ import annotations

import argparse
import fcntl
import gzip
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LOCK_PATH = ROOT / "RuntimeLocks" / "mihomo.lock.json"
SUPPORTED_ARCHITECTURES = ("arm64", "x86_64")
GENERATED_RESOURCE_NAMES = (
    "arm64",
    "x86_64",
    "GeoData",
    "clash_ui",
    "ThirdPartyLicenses",
    "MANIFEST.json",
    "bin",
    "VERSION",
)
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


class RuntimeToolError(Exception):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def directory_digest(root: Path, excluded_names: Iterable[str] = ()) -> str:
    excluded = set(excluded_names)
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        if path.name in excluded:
            continue
        if path.is_symlink():
            raise RuntimeToolError(f"Unexpected symbolic link in prepared runtime: {path}")
        if not path.is_file():
            continue
        relative_path = path.relative_to(root).as_posix().encode("utf-8")
        digest.update(relative_path)
        digest.update(b"\0")
        digest.update(bytes.fromhex(sha256_file(path)))
    return digest.hexdigest()


def atomic_write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise RuntimeToolError(f"{label} must be an object")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise RuntimeToolError(f"{label} must be a non-empty string")
    return value


def validate_digest(value: Any, label: str) -> str:
    digest = require_string(value, label)
    if not SHA256_PATTERN.fullmatch(digest):
        raise RuntimeToolError(f"{label} must be a lowercase SHA-256 digest")
    return digest


def artifact_items(lock: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    mihomo = require_mapping(lock.get("mihomo"), "mihomo")
    artifacts = require_mapping(mihomo.get("artifacts"), "mihomo.artifacts")
    items: list[tuple[str, dict[str, Any]]] = []
    for architecture in SUPPORTED_ARCHITECTURES:
        items.append(
            (
                f"mihomo.artifacts.{architecture}",
                require_mapping(artifacts.get(architecture), f"mihomo.artifacts.{architecture}"),
            )
        )

    items.append(("mihomo.source", require_mapping(mihomo.get("source"), "mihomo.source")))
    geo_data = require_mapping(lock.get("geoData"), "geoData")
    geo_files = geo_data.get("files")
    if not isinstance(geo_files, list) or not geo_files:
        raise RuntimeToolError("geoData.files must be a non-empty array")
    for index, item in enumerate(geo_files):
        items.append((f"geoData.files[{index}]", require_mapping(item, f"geoData.files[{index}]")))

    licenses = lock.get("licenses")
    if not isinstance(licenses, list) or not licenses:
        raise RuntimeToolError("licenses must be a non-empty array")
    for index, item in enumerate(licenses):
        items.append((f"licenses[{index}]", require_mapping(item, f"licenses[{index}]")))
    return items


def load_and_validate_lock(path: Path) -> tuple[dict[str, Any], bytes]:
    try:
        raw_data = path.read_bytes()
    except FileNotFoundError as error:
        raise RuntimeToolError(f"Runtime lock does not exist: {path}") from error
    try:
        lock = json.loads(raw_data)
    except json.JSONDecodeError as error:
        raise RuntimeToolError(f"Runtime lock is invalid JSON: {error}") from error
    lock = require_mapping(lock, "runtime lock")
    if lock.get("schemaVersion") != 1:
        raise RuntimeToolError("Unsupported runtime lock schemaVersion")

    hosts = lock.get("allowedDownloadHosts")
    if not isinstance(hosts, list) or not hosts or not all(isinstance(host, str) for host in hosts):
        raise RuntimeToolError("allowedDownloadHosts must be a non-empty string array")
    allowed_hosts = set(hosts)

    deployment_target = require_string(lock.get("deploymentTarget"), "deploymentTarget")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", deployment_target):
        raise RuntimeToolError("deploymentTarget must be a macOS version")

    mihomo = require_mapping(lock.get("mihomo"), "mihomo")
    require_string(mihomo.get("repository"), "mihomo.repository")
    require_string(mihomo.get("tag"), "mihomo.tag")
    artifacts = require_mapping(mihomo.get("artifacts"), "mihomo.artifacts")
    for architecture in SUPPORTED_ARCHITECTURES:
        artifact = require_mapping(artifacts.get(architecture), f"mihomo.artifacts.{architecture}")
        validate_digest(
            artifact.get("executableSha256"),
            f"mihomo.artifacts.{architecture}.executableSha256",
        )
        require_string(
            artifact.get("versionOutput"),
            f"mihomo.artifacts.{architecture}.versionOutput",
        )

    geo_data = require_mapping(lock.get("geoData"), "geoData")
    require_string(geo_data.get("version"), "geoData.version")

    for label, artifact in artifact_items(lock):
        url = require_string(artifact.get("url"), f"{label}.url")
        parsed = urlparse(url)
        if parsed.scheme != "https" or parsed.hostname not in allowed_hosts:
            raise RuntimeToolError(f"{label}.url is not on an allowed HTTPS host: {url}")
        if parsed.username or parsed.password or parsed.fragment:
            raise RuntimeToolError(f"{label}.url contains forbidden URL components")
        validate_digest(artifact.get("sha256"), f"{label}.sha256")
        if label.startswith("geoData.files") or label.startswith("licenses"):
            name = require_string(artifact.get("name"), f"{label}.name")
            if Path(name).name != name:
                raise RuntimeToolError(f"{label}.name must be a plain filename")

    return lock, raw_data


def cache_root() -> Path:
    configured = os.environ.get("DOUMEOW_RUNTIME_CACHE_DIR")
    if configured:
        return Path(configured).expanduser().resolve()
    return (
        Path.home()
        / "Library"
        / "Caches"
        / "com.dou.meow"
        / "vendor"
        / "mihomo"
    )


def normalize_architectures(values: list[str] | None) -> list[str]:
    requested = values or ["current"]
    architectures: list[str] = []
    for value in requested:
        for item in value.split():
            if item == "all":
                candidates = list(SUPPORTED_ARCHITECTURES)
            elif item == "current":
                machine = platform.machine()
                if machine not in SUPPORTED_ARCHITECTURES:
                    raise RuntimeToolError(f"Unsupported current architecture: {machine}")
                candidates = [machine]
            else:
                candidates = [item]
            for architecture in candidates:
                if architecture not in SUPPORTED_ARCHITECTURES:
                    raise RuntimeToolError(f"Unsupported architecture: {architecture}")
                if architecture not in architectures:
                    architectures.append(architecture)
    if not architectures:
        raise RuntimeToolError("At least one architecture is required")
    return architectures


def run_curl(url: str, destination: Path, resume: bool) -> None:
    command = [
        "/usr/bin/curl",
        "--fail",
        "--location",
        "--retry",
        "3",
        "--retry-all-errors",
        "--silent",
        "--show-error",
        "--netrc-optional",
    ]
    if resume and destination.exists() and destination.stat().st_size > 0:
        command += ["--continue-at", "-"]
    command += ["--output", str(destination), url]
    result = subprocess.run(command, check=False)
    if result.returncode != 0:
        raise RuntimeToolError(f"Download failed with curl status {result.returncode}: {url}")


def cached_artifact(
    item: dict[str, Any],
    label: str,
    offline: bool,
) -> Path:
    expected_digest = item["sha256"]
    artifacts_root = cache_root() / "artifacts"
    artifacts_root.mkdir(parents=True, exist_ok=True)
    destination = artifacts_root / expected_digest
    lock_path = artifacts_root / f".{expected_digest}.lock"

    with lock_path.open("a+b") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        if destination.is_file() and sha256_file(destination) == expected_digest:
            return destination
        if destination.exists():
            destination.unlink()
        if offline:
            raise RuntimeToolError(
                f"Missing cached artifact for {label}. Run make setup first."
            )

        partial = artifacts_root / f".{expected_digest}.partial"
        print(f"Downloading {label}")
        print(f"  URL: {item['url']}")
        print(f"  Cache: {destination}")
        try:
            run_curl(item["url"], partial, resume=True)
        except RuntimeToolError:
            if not partial.exists():
                raise
            partial.unlink()
            run_curl(item["url"], partial, resume=False)

        actual_digest = sha256_file(partial)
        if actual_digest != expected_digest:
            partial.unlink()
            raise RuntimeToolError(
                f"SHA-256 mismatch for {label}: expected {expected_digest}, got {actual_digest}"
            )
        os.replace(partial, destination)
        return destination


def replace_directory(temporary: Path, destination: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    os.replace(temporary, destination)


def common_state_is_valid(common_root: Path, lock_digest: str) -> bool:
    state_path = common_root / ".prepared.json"
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return False
    if state.get("lockSha256") != lock_digest:
        return False
    try:
        actual_digest = directory_digest(common_root, excluded_names={".prepared.json"})
    except RuntimeToolError:
        return False
    return state.get("treeSha256") == actual_digest


def prepare_common(lock: dict[str, Any], lock_digest: str, offline: bool) -> Path:
    resolved_root = cache_root() / "resolved" / lock_digest
    common_root = resolved_root / "common"
    resolved_root.mkdir(parents=True, exist_ok=True)
    lock_path = resolved_root / ".common.lock"
    with lock_path.open("a+b") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        if common_state_is_valid(common_root, lock_digest):
            return common_root

        temporary = resolved_root / f".common.{uuid.uuid4().hex}.tmp"
        temporary.mkdir(parents=True)
        try:
            geo_root = temporary / "GeoData"
            geo_root.mkdir()
            for item in lock["geoData"]["files"]:
                source = cached_artifact(item, f"GeoData {item['name']}", offline)
                shutil.copy2(source, geo_root / item["name"])

            license_root = temporary / "ThirdPartyLicenses"
            license_root.mkdir()
            for item in lock["licenses"]:
                source = cached_artifact(item, f"license {item['name']}", offline)
                shutil.copy2(source, license_root / item["name"])

            provenance_lines = [
                "DouMeow bundled runtime provenance",
                "",
                f"Mihomo: {lock['mihomo']['tag']} ({lock['mihomo']['repository']})",
                f"GeoData: {lock['geoData']['version']}",
                "",
                "Locked artifacts:",
            ]
            for label, item in artifact_items(lock):
                provenance_lines.append(f"- {label}: {item['url']}")
                provenance_lines.append(f"  SHA-256: {item['sha256']}")
            (license_root / "PROVENANCE.txt").write_text(
                "\n".join(provenance_lines) + "\n",
                encoding="utf-8",
            )

            tree_digest = directory_digest(temporary)
            atomic_write_json(
                temporary / ".prepared.json",
                {"lockSha256": lock_digest, "treeSha256": tree_digest},
            )
            replace_directory(temporary, common_root)
        except Exception:
            if temporary.exists():
                shutil.rmtree(temporary)
            raise
    return common_root


def architecture_state_is_valid(
    architecture_root: Path,
    lock_digest: str,
    artifact: dict[str, Any],
) -> bool:
    executable = architecture_root / "bin" / "mihomo"
    state_path = architecture_root / ".prepared.json"
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return False
    return (
        state.get("lockSha256") == lock_digest
        and state.get("executableSha256") == artifact["executableSha256"]
        and executable.is_file()
        and sha256_file(executable) == artifact["executableSha256"]
    )


def validate_macho(executable: Path, architecture: str, deployment_target: str) -> None:
    file_result = subprocess.run(
        ["/usr/bin/file", str(executable)],
        check=True,
        capture_output=True,
        text=True,
    )
    expected_architecture = "x86_64" if architecture == "x86_64" else "arm64"
    if "Mach-O 64-bit executable" not in file_result.stdout or expected_architecture not in file_result.stdout:
        raise RuntimeToolError(
            f"Mihomo architecture mismatch for {architecture}: {file_result.stdout.strip()}"
        )

    vtool = subprocess.run(
        ["/usr/bin/xcrun", "vtool", "-show-build", str(executable)],
        check=False,
        capture_output=True,
        text=True,
    )
    if vtool.returncode != 0:
        raise RuntimeToolError(f"Unable to inspect Mihomo minimum macOS version: {vtool.stderr.strip()}")
    minimum_versions = re.findall(r"^\s*minos\s+([0-9]+(?:\.[0-9]+)*)", vtool.stdout, re.MULTILINE)
    if not minimum_versions:
        raise RuntimeToolError("Mihomo does not declare a minimum macOS version")

    def version_tuple(value: str) -> tuple[int, ...]:
        return tuple(int(part) for part in value.split("."))

    target = version_tuple(deployment_target)
    for minimum_version in minimum_versions:
        if version_tuple(minimum_version) > target:
            raise RuntimeToolError(
                f"Mihomo requires macOS {minimum_version}, above deployment target {deployment_target}"
            )


def validate_version_output(
    executable: Path,
    architecture: str,
    expected_output: str,
) -> None:
    try:
        result = subprocess.run(
            [str(executable), "-v"],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except OSError as error:
        if platform.machine() == architecture:
            raise RuntimeToolError(f"Unable to execute Mihomo {architecture}: {error}") from error
        print(f"Skipping {architecture} version execution on {platform.machine()}: {error}")
        return
    if result.returncode != 0:
        if platform.machine() == architecture:
            raise RuntimeToolError(
                f"Mihomo {architecture} version command failed: {result.stderr.strip()}"
            )
        print(f"Skipping {architecture} version execution on {platform.machine()}")
        return
    actual_output = next((line for line in result.stdout.splitlines() if line.strip()), "")
    if actual_output != expected_output:
        raise RuntimeToolError(
            f"Mihomo {architecture} version mismatch: expected {expected_output!r}, got {actual_output!r}"
        )


def prepare_architecture(
    lock: dict[str, Any],
    lock_digest: str,
    architecture: str,
    offline: bool,
) -> Path:
    artifact = lock["mihomo"]["artifacts"][architecture]
    resolved_root = cache_root() / "resolved" / lock_digest
    architecture_root = resolved_root / architecture
    resolved_root.mkdir(parents=True, exist_ok=True)
    lock_path = resolved_root / f".{architecture}.lock"
    with lock_path.open("a+b") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        if architecture_state_is_valid(architecture_root, lock_digest, artifact):
            return architecture_root

        temporary = resolved_root / f".{architecture}.{uuid.uuid4().hex}.tmp"
        executable = temporary / "bin" / "mihomo"
        executable.parent.mkdir(parents=True)
        try:
            archive = cached_artifact(artifact, f"Mihomo {architecture}", offline)
            with gzip.open(archive, "rb") as source, executable.open("wb") as destination:
                shutil.copyfileobj(source, destination, length=1024 * 1024)
            executable.chmod(0o755)
            actual_digest = sha256_file(executable)
            if actual_digest != artifact["executableSha256"]:
                raise RuntimeToolError(
                    f"Mihomo {architecture} executable SHA-256 mismatch: "
                    f"expected {artifact['executableSha256']}, got {actual_digest}"
                )
            validate_macho(executable, architecture, lock["deploymentTarget"])
            validate_version_output(executable, architecture, artifact["versionOutput"])
            (temporary / "VERSION").write_text(artifact["versionOutput"] + "\n", encoding="utf-8")
            atomic_write_json(
                temporary / ".prepared.json",
                {
                    "archiveSha256": artifact["sha256"],
                    "executableSha256": artifact["executableSha256"],
                    "lockSha256": lock_digest,
                    "versionOutput": artifact["versionOutput"],
                },
            )
            replace_directory(temporary, architecture_root)
        except Exception:
            if temporary.exists():
                shutil.rmtree(temporary)
            raise
    return architecture_root


def prepared_paths(
    lock: dict[str, Any],
    lock_digest: str,
    architectures: list[str],
) -> tuple[Path, dict[str, Path]]:
    common_root = cache_root() / "resolved" / lock_digest / "common"
    if not common_state_is_valid(common_root, lock_digest):
        raise RuntimeToolError(
            "Prepared common Mihomo resources are missing or invalid. "
            "Run make setup first."
        )
    paths: dict[str, Path] = {}
    for architecture in architectures:
        artifact = lock["mihomo"]["artifacts"][architecture]
        architecture_root = cache_root() / "resolved" / lock_digest / architecture
        if not architecture_state_is_valid(architecture_root, lock_digest, artifact):
            raise RuntimeToolError(
                f"Prepared Mihomo {architecture} runtime is missing or invalid. "
                "Run make setup first."
            )
        paths[architecture] = architecture_root
    return common_root, paths


def remove_generated_resources(destination: Path) -> None:
    if destination == Path(destination.anchor) or len(destination.parts) < 4:
        raise RuntimeToolError(f"Refusing unsafe staging destination: {destination}")
    destination.mkdir(parents=True, exist_ok=True)
    for name in GENERATED_RESOURCE_NAMES:
        path = destination / name
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        elif path.exists() or path.is_symlink():
            path.unlink()


def stage_runtime(
    lock: dict[str, Any],
    lock_digest: str,
    architectures: list[str],
    destination: Path,
) -> None:
    common_root, architecture_paths = prepared_paths(lock, lock_digest, architectures)
    destination = destination.expanduser().resolve()
    remove_generated_resources(destination)

    for name in ("GeoData", "ThirdPartyLicenses"):
        shutil.copytree(common_root / name, destination / name)

    for architecture, source in architecture_paths.items():
        target = destination / architecture
        shutil.copytree(source, target, ignore=shutil.ignore_patterns(".prepared.json"))
        executable = target / "bin" / "mihomo"
        subprocess.run(["/usr/bin/xattr", "-cr", str(target)], check=False)
        subprocess.run(
            ["/usr/bin/codesign", "--force", "--sign", "-", str(executable)],
            check=True,
            capture_output=True,
            text=True,
        )

    manifest = {
        "schemaVersion": 1,
        "lockSha256": lock_digest,
        "mihomo": {
            "tag": lock["mihomo"]["tag"],
            "architectures": {
                architecture: {
                    "archiveSha256": lock["mihomo"]["artifacts"][architecture]["sha256"],
                    "executableSha256": lock["mihomo"]["artifacts"][architecture][
                        "executableSha256"
                    ],
                    "version": lock["mihomo"]["artifacts"][architecture]["versionOutput"],
                }
                for architecture in architectures
            },
        },
        "geoData": {
            "version": lock["geoData"]["version"],
            "files": {
                item["name"]: item["sha256"] for item in lock["geoData"]["files"]
            },
        },
    }
    atomic_write_json(destination / "MANIFEST.json", manifest)
    print(f"Staged Mihomo runtime ({', '.join(architectures)}) -> {destination}")


def prepare_runtime(
    lock: dict[str, Any],
    lock_digest: str,
    architectures: list[str],
    offline: bool,
) -> None:
    prepare_common(lock, lock_digest, offline)
    for architecture in architectures:
        prepare_architecture(lock, lock_digest, architecture, offline)
    print(f"Prepared Mihomo runtime ({', '.join(architectures)})")
    print(f"Cache: {cache_root() / 'resolved' / lock_digest}")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK_PATH)
    subparsers = parser.add_subparsers(dest="command", required=True)

    for command_name in ("prepare", "verify"):
        command = subparsers.add_parser(command_name)
        command.add_argument("--arch", action="append", dest="architectures")
        if command_name == "prepare":
            command.add_argument("--offline", action="store_true")

    stage = subparsers.add_parser("stage")
    stage.add_argument("--arch", action="append", dest="architectures")
    stage.add_argument("--destination", required=True, type=Path)

    subparsers.add_parser("validate-lock")
    subparsers.add_parser("cache-path")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    lock, lock_data = load_and_validate_lock(arguments.lock.resolve())
    lock_digest = sha256_bytes(lock_data)

    if arguments.command == "validate-lock":
        print(f"Runtime lock is valid: {arguments.lock}")
        print(f"Lock SHA-256: {lock_digest}")
        return 0
    if arguments.command == "cache-path":
        print(cache_root() / "resolved" / lock_digest)
        return 0

    architectures = normalize_architectures(arguments.architectures)
    if arguments.command == "prepare":
        prepare_runtime(lock, lock_digest, architectures, arguments.offline)
    elif arguments.command == "verify":
        common_root, paths = prepared_paths(lock, lock_digest, architectures)
        print(f"Verified common runtime resources: {common_root}")
        for architecture, path in paths.items():
            print(f"Verified Mihomo {architecture}: {path / 'bin' / 'mihomo'}")
    elif arguments.command == "stage":
        stage_runtime(lock, lock_digest, architectures, arguments.destination)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeToolError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
