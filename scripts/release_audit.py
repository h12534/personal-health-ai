"""Static release guardrails that require no credentials or external services."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = (
    ".env.production.example",
    ".env.staging.example",
    "docker-compose.production.yml",
    "docker-compose.staging.yml",
    "deploy/nginx/nginx.production.conf",
    "mobile/ios/Runner/Info.plist",
    "mobile/ios/Runner/Runner.entitlements",
)
FORBIDDEN_TRACKED_NAMES = {".env", ".env.production", ".env.staging"}
FORBIDDEN_SUFFIXES = {
    ".p8",
    ".p12",
    ".mobileprovision",
    ".dump",
    ".sqlite",
    ".sqlite3",
}


def tracked_files() -> list[Path]:
    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={ROOT.as_posix()}",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    return [ROOT / value.decode() for value in result.stdout.split(b"\0") if value]


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    for relative in REQUIRED:
        if not (ROOT / relative).is_file():
            errors.append(f"missing required release file: {relative}")

    try:
        files = tracked_files()
    except RuntimeError as exc:
        errors.append(f"cannot enumerate tracked files: {exc}")
        files = []

    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        if path.name in FORBIDDEN_TRACKED_NAMES or path.suffix.lower() in FORBIDDEN_SUFFIXES:
            errors.append(f"sensitive artifact is tracked: {relative}")
        if "storage/backups/" in f"{relative}/" and path.name != ".gitkeep":
            errors.append(f"database backup is tracked: {relative}")

    text_files = [path for path in files if path.suffix.lower() in {".py", ".dart", ".yml", ".yaml", ".plist", ".md", ".example"}]
    secret_patterns = {
        "private key": re.compile(r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----"),
        "OpenAI-style key": re.compile(r"\bsk-[A-Za-z0-9]{20,}\b"),
        "AWS access key": re.compile(r"\bAKIA[A-Z0-9]{16}\b"),
    }
    for path in text_files:
        content = path.read_text(encoding="utf-8", errors="ignore")
        for label, pattern in secret_patterns.items():
            if pattern.search(content):
                errors.append(f"possible {label} in {path.relative_to(ROOT).as_posix()}")

    pubspec = (ROOT / "mobile/pubspec.yaml").read_text(encoding="utf-8")
    if "version: 0.1.0-beta.1+" not in pubspec:
        errors.append("mobile/pubspec.yaml is not on 0.1.0-beta.1 with a build number")

    app_config = (ROOT / "mobile/lib/core/config/app_config.dart").read_text(encoding="utf-8")
    for guardrail in ("cannot use localhost", "must use HTTPS"):
        if guardrail not in app_config:
            errors.append(f"mobile API guardrail is missing: {guardrail}")

    info_plist = (ROOT / "mobile/ios/Runner/Info.plist").read_text(encoding="utf-8")
    if "NSAllowsArbitraryLoads" in info_plist:
        errors.append("broad ATS override is present in iOS Info.plist")

    nginx = (ROOT / "deploy/nginx/nginx.production.conf").read_text(encoding="utf-8")
    for expected in ("TLSv1.2 TLSv1.3", "Strict-Transport-Security", "server_tokens off"):
        if expected not in nginx:
            errors.append(f"nginx production guardrail is missing: {expected}")

    production = (ROOT / "docker-compose.production.yml").read_text(encoding="utf-8")
    if "5432:5432" in production or "6379:6379" in production:
        errors.append("production database or Redis is exposed on a host port")
    warnings.extend(
        [
            "external gate: GitHub remote and CI run evidence are unavailable locally",
            "external gate: macOS/Xcode/iPhone/TestFlight require Apple infrastructure",
            "external gate: staging HTTPS and real providers require owner-supplied access",
        ]
    )

    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")
    if errors:
        print(f"release_audit=failed errors={len(errors)} warnings={len(warnings)}")
        return 1
    print(f"release_audit=passed errors=0 warnings={len(warnings)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
