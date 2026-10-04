"""Build and package unsigned device IPAs. No Apple credentials or signing."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import zipfile
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"
VARIANTS = {
    "healthkit": "PERSONAL_SIDELOAD_HEALTHKIT",
    "free": "PERSONAL_SIDELOAD_FREE",
}


def configuration(variant: str) -> dict[str, str]:
    if variant not in VARIANTS:
        raise ValueError("Unknown personal sideload variant")
    values = {
        "APP_DISTRIBUTION": "personal_sideload",
        "PERSONAL_SIDELOAD_FREE": str(variant == "free").lower(),
        "APP_ENV": "staging",
        "APP_VERSION": os.environ.get("APP_VERSION", "0.1.0"),
        "BUILD_NUMBER": os.environ.get("BUILD_NUMBER", "2"),
        "API_BASE_URL": os.environ.get(
            "API_BASE_URL", "https://staging-api.personal-health.invalid/api/v1"
        ),
    }
    if not re.fullmatch(r"\d+\.\d+\.\d+", values["APP_VERSION"]):
        raise ValueError("Use a numeric iOS marketing version")
    if not re.fullmatch(r"[1-9]\d{0,3}(?:\.\d{1,2}){0,2}", values["BUILD_NUMBER"]):
        raise ValueError("Use an Apple-compatible numeric build number")
    uri = urlsplit(values["API_BASE_URL"])
    if (
        uri.scheme != "https"
        or not uri.hostname
        or uri.username
        or uri.password
        or uri.query
        or uri.fragment
        or uri.hostname in {"localhost", "127.0.0.1", "::1"}
        or uri.path.rstrip("/") != "/api/v1"
    ):
        raise ValueError("Personal build API must be credential-free HTTPS /api/v1")
    return values


def build(variant: str) -> None:
    config = configuration(variant)
    environment = {**os.environ, **config}
    subprocess.run(
        ["dart", "run", "tool/configure_ios.dart"],
        cwd=MOBILE,
        env=environment,
        check=True,
    )
    subprocess.run(
        [
            "flutter",
            "build",
            "ios",
            "--release",
            "--no-codesign",
            f"--build-name={config['APP_VERSION']}",
            f"--build-number={config['BUILD_NUMBER']}",
            *(f"--dart-define={key}={value}" for key, value in config.items()),
        ],
        cwd=MOBILE,
        env=environment,
        check=True,
    )


def validate_unsigned_arm64(executable: Path) -> None:
    # The device Runner must not be a simulator binary, a script, or signed code.
    with executable.open("rb") as handle:
        header = handle.read(32)
        if len(header) != 32 or header[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError("Expected a little-endian 64-bit device Mach-O")
        cpu, _, filetype, commands, size = struct.unpack_from("<IIIII", header, 4)
        if cpu != 0x0100000C or filetype != 2 or size > 16 * 1024 * 1024:
            raise ValueError("Expected an arm64 MH_EXECUTE device Runner")
        content = handle.read(size)
    offset = 0
    for _ in range(commands):
        if offset + 8 > len(content):
            raise ValueError("Truncated Mach-O load commands")
        command, length = struct.unpack_from("<II", content, offset)
        if command == 0x1D:
            raise ValueError(
                "Runner contains LC_CODE_SIGNATURE; unsigned build required"
            )
        if length < 8 or offset + length > len(content):
            raise ValueError("Invalid Mach-O load command")
        # LC_BUILD_VERSION: 1=macOS, 2=iOS, 7=iOS simulator.
        if command == 0x32 and (
            length < 24 or struct.unpack_from("<I", content, offset + 8)[0] != 2
        ):
            raise ValueError("Runner was not built for the iOS device platform")
        offset += length
    if offset != len(content):
        raise ValueError("Unexpected Mach-O load command size")


def package(
    app: Path,
    output: Path,
    variant: str,
    config: dict[str, str],
    commit: str,
    requested: dict,
) -> dict:
    app = app.resolve()
    if app.name != "Runner.app" or not app.is_dir():
        raise ValueError("Expected the built Runner.app directory")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Evidence requires the full commit SHA")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    expected = {
        "CFBundleShortVersionString": config["APP_VERSION"],
        "CFBundleVersion": config["BUILD_NUMBER"],
        "AppDistribution": config["APP_DISTRIBUTION"],
        "PersonalSideloadFree": config["PERSONAL_SIDELOAD_FREE"],
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f"Native metadata mismatch: {key}")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("IPA must contain an iPhoneOS device build")
    if info.get("MinimumOSVersion") != "16.0":
        raise ValueError("Expected the existing iOS 16 deployment target")
    executable_name = info.get("CFBundleExecutable", "")
    if not executable_name or Path(executable_name).name != executable_name:
        raise ValueError("Unsafe executable name")
    validate_unsigned_arm64(app / executable_name)
    if (app / "_CodeSignature").exists():
        raise ValueError("Runner.app unexpectedly contains a signature envelope")
    if (
        bool(requested.get("com.apple.developer.healthkit")) != (variant == "healthkit")
        or "aps-environment" in requested
    ):
        raise ValueError("Unexpected HealthKit / APNs entitlement request")
    files = sorted(app.rglob("*"))
    forbidden = {
        ".p8",
        ".p12",
        ".pfx",
        ".key",
        ".pem",
        ".cer",
        ".mobileprovision",
        ".provisionprofile",
    }
    for path in files:
        if path.suffix.lower() in forbidden:
            raise ValueError("Signing material must not enter the unsigned artifact")
        if path.is_symlink() and (
            Path(os.readlink(path)).is_absolute()
            or not path.resolve().is_relative_to(app)
        ):
            raise ValueError("Symlink escapes Runner.app")
    output.mkdir(parents=True, exist_ok=True)
    filename = (
        "personal-health-ios-unsigned.ipa"
        if variant == "healthkit"
        else "personal-health-ios-free-unsigned.ipa"
    )
    ipa = output / filename
    with zipfile.ZipFile(
        ipa, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6
    ) as archive:
        for path in [app, *files]:
            name = "Payload/Runner.app" + (
                "/" + path.relative_to(app).as_posix() if path != app else ""
            )
            if path.is_symlink():
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, os.readlink(path).encode())
            else:
                entry = zipfile.ZipInfo.from_file(path, name)
                entry.create_system = 3
                entry.compress_type = zipfile.ZIP_DEFLATED
                if path == app / executable_name:
                    # Device executables must keep Unix +x even when guardrail
                    # fixtures are generated on Windows (chmod cannot set it).
                    entry.external_attr = (stat.S_IFREG | 0o755) << 16
                if path.is_dir():
                    archive.writestr(entry, b"")
                else:
                    with path.open("rb") as source, archive.open(entry, "w") as target:
                        shutil.copyfileobj(source, target)
    with zipfile.ZipFile(ipa) as archive:
        if (
            archive.testzip()
            or "Payload/Runner.app/Info.plist" not in archive.namelist()
        ):
            raise ValueError("IPA ZIP integrity / Payload layout verification failed")
    with ipa.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    uri = urlsplit(config["API_BASE_URL"])
    evidence = {
        "distribution": "private_personal_sideload",
        "flavor": VARIANTS[variant],
        "artifact": filename,
        "sha256": digest,
        "commit_sha": commit,
        "workflow_run": os.environ.get("GITHUB_RUN_ID"),
        "workflow_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "version": info["CFBundleShortVersionString"],
        "build_number": info["CFBundleVersion"],
        "bundle_identifier": info["CFBundleIdentifier"],
        "display_name": info["CFBundleDisplayName"],
        "minimum_ios": info["MinimumOSVersion"],
        "api_host": uri.hostname,
        "api_configured": not uri.hostname.endswith((".invalid", ".example", ".local")),
        "api_acceptance": "NOT_RUN",
        "remote_push_enabled": False,
        "requested_entitlements": requested,
        "signed_entitlements": "NONE_IN_UNSIGNED_RUNNER",
        "runner_unsigned_verified": True,
        "windows_resigning": "NOT_RUN",
        "iphone_install": "NOT_RUN",
        "iphone_launch": "NOT_RUN",
        "healthkit_acceptance": "NOT_RUN",
    }
    (output / "personal-sideload-evidence.json").write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (output / "SHA256SUMS").write_text(f"{digest}  {filename}\n", encoding="utf-8")
    # This request file is documentation, NOT a code signature or a profile.
    (output / "requested-entitlements.plist").write_bytes(plistlib.dumps(requested))
    if not evidence["api_configured"]:
        print(
            "::warning::Placeholder API host: installation/startup can be tested, real login/AI/API acceptance cannot."
        )
    print(json.dumps(evidence, ensure_ascii=False))
    return evidence


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("build", "package"))
    parser.add_argument("--variant", choices=VARIANTS, required=True)
    args = parser.parse_args()
    if args.phase == "build":
        build(args.variant)
        return
    config = configuration(args.variant)
    source = (
        MOBILE
        / "ios/Runner"
        / (
            "PersonalSideloadFree.entitlements"
            if args.variant == "free"
            else "Runner.entitlements"
        )
    )
    package(
        MOBILE / "build/ios/iphoneos/Runner.app",
        MOBILE / "build/personal-sideload" / args.variant,
        args.variant,
        config,
        os.environ["GITHUB_SHA"],
        plistlib.loads(source.read_bytes()),
    )


if __name__ == "__main__":
    main()
