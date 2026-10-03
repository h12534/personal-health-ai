"""Cloud-only signing/export/upload. Secret values never enter argv or evidence."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Missing configuration: {name}")
    return value


def validate_config(config: dict[str, str]) -> None:
    for name in (
        "IOS_TEAM_ID",
        "IOS_BUNDLE_ID",
        "APP_DISPLAY_NAME",
        "ASC_APP_ID",
        "API_BASE_URL",
        "APP_VERSION",
        "BUILD_NUMBER",
    ):
        if not config.get(name, "").strip():
            raise ValueError(f"Missing configuration: {name}")
    if not re.fullmatch(r"[A-Z0-9]{10}", config["IOS_TEAM_ID"]):
        raise ValueError("IOS_TEAM_ID must be the 10-character Apple Team ID")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", config["IOS_BUNDLE_ID"]):
        raise ValueError("IOS_BUNDLE_ID must be an explicit reverse-DNS identifier")
    if any(char in config["APP_DISPLAY_NAME"] for char in "\n\r$;/"):
        raise ValueError("APP_DISPLAY_NAME contains unsupported xcconfig characters")
    if not config["ASC_APP_ID"].isdigit():
        raise ValueError("ASC_APP_ID must be the numeric App Store Connect App ID")
    if not re.fullmatch(r"\d+\.\d+\.\d+", config["APP_VERSION"]):
        raise ValueError(
            "APP_VERSION must be numeric major.minor.patch, not beta semver"
        )
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", config["BUILD_NUMBER"]):
        raise ValueError(
            "BUILD_NUMBER must be an Apple-compatible numeric build number"
        )
    components = config["BUILD_NUMBER"].split(".")
    if (
        int(components[0]) < 1
        or len(components[0]) > 4
        or any(len(part) > 2 for part in components[1:])
    ):
        raise ValueError(
            "BUILD_NUMBER requires a positive <=4-digit first component and <=2-digit remaining components"
        )
    uri = urlsplit(config["API_BASE_URL"])
    host = (uri.hostname or "").lower()
    if (
        uri.scheme != "https"
        or not host
        or uri.username
        or uri.password
        or uri.query
        or uri.fragment
        or host in {"localhost", "127.0.0.1", "::1"}
        or host.endswith((".invalid", ".localhost", ".local", ".example"))
        or host in {"example.com", "example.org", "example.net"}
        or not uri.path.rstrip("/").endswith("/api/v1")
    ):
        raise ValueError(
            "API_BASE_URL must be a real credential-free HTTPS /api/v1 URL"
        )
    if config.get("APP_ENV") != "staging":
        raise ValueError("This owner-only Beta workflow uses APP_ENV=staging")
    if config.get("IOS_SIGNING_MODE", "automatic") not in {"automatic", "manual"}:
        raise ValueError("IOS_SIGNING_MODE must be automatic or manual")


def signing_dir() -> Path:
    root = Path(required("RUNNER_TEMP")).resolve()
    target = Path(required("SIGNING_DIR")).resolve()
    if target.parent != root or target.name != "health-ios-signing":
        raise ValueError("SIGNING_DIR must be the dedicated child of RUNNER_TEMP")
    return target


def run(*args: str, capture: bool = False) -> bytes:
    result = subprocess.run(
        args,
        cwd=MOBILE,
        check=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    return result.stdout if capture else b""


def validate_profile(profile: dict, config: dict[str, str]) -> None:
    entitlements = profile.get("Entitlements", {})
    if profile.get("TeamIdentifier") != [config["IOS_TEAM_ID"]]:
        raise ValueError("Provisioning profile Team ID mismatch")
    identifier = f"{profile.get('ApplicationIdentifierPrefix', [''])[0]}.{config['IOS_BUNDLE_ID']}"
    if entitlements.get("application-identifier") != identifier:
        raise ValueError("Provisioning profile Bundle ID mismatch or wildcard profile")
    if entitlements.get("com.apple.developer.healthkit") is not True:
        raise ValueError("Provisioning profile lacks HealthKit capability")
    if (
        profile.get("ProvisionedDevices")
        or profile.get("ProvisionsAllDevices")
        or entitlements.get("get-task-allow", False)
    ):
        raise ValueError("An App Store distribution profile is required")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, dt.datetime) or expiry.replace(
        tzinfo=dt.UTC
    ) <= dt.datetime.now(dt.UTC):
        raise ValueError("Provisioning profile is expired or has no expiry")
    if not re.fullmatch(r"[A-Fa-f0-9-]{36}", str(profile.get("UUID", ""))):
        raise ValueError("Invalid provisioning profile UUID")


def read_profile(path: Path) -> dict:
    return plistlib.loads(run("security", "cms", "-D", "-i", str(path), capture=True))


def preflight() -> None:
    validate_config(dict(os.environ))
    base = urlsplit(required("API_BASE_URL"))
    url = base._replace(path="/health/ready", query="", fragment="").geturl()
    with urllib.request.urlopen(url, timeout=20) as response:
        data = json.load(response)
    if data.get("status") != "ready":
        raise ValueError("Staging backend /health/ready is not ready")
    print("Owner configuration and staging readiness validated; signing has NOT run")


def configure_release_identity(project: Path, bundle_id: str) -> None:
    """Resolve Runner identity in the disposable CI checkout for signing tools."""
    content = project.read_text(encoding="utf-8")
    marker = 'PRODUCT_BUNDLE_IDENTIFIER = "$(IOS_BUNDLE_ID)";'
    if content.count(marker) != 3:
        raise ValueError(
            "Expected three configurable Runner identities; refusing a blind project rewrite"
        )
    project.write_text(
        content.replace(marker, f'PRODUCT_BUNDLE_IDENTIFIER = "{bundle_id}";'),
        encoding="utf-8",
    )


def validate_app_record() -> None:
    record = json.loads(
        run(
            "app-store-connect",
            "apps",
            "get",
            required("ASC_APP_ID"),
            "--json",
            "--silent",
            "--private-key",
            "@env:APP_STORE_CONNECT_PRIVATE_KEY",
            capture=True,
        )
    )
    record = record.get("data", record)
    if str(record.get("id")) != required("ASC_APP_ID") or record.get(
        "attributes", {}
    ).get("bundleId") != required("IOS_BUNDLE_ID"):
        raise ValueError(
            "App Store Connect record does not match owner App ID / Bundle ID"
        )


def sign() -> None:
    os.umask(0o077)
    validate_config(dict(os.environ))
    target = signing_dir()
    target.mkdir(mode=0o700, parents=True, exist_ok=True)
    certificate_dir = target / "certificates"
    profile_dir = target / "profiles"
    certificate_dir.mkdir(mode=0o700, exist_ok=True)
    profile_dir.mkdir(mode=0o700, exist_ok=True)
    os.environ["IOS_TEMP_KEYCHAIN_PASSWORD"] = secrets.token_urlsafe(32)
    for name in (
        "APP_STORE_CONNECT_ISSUER_ID",
        "APP_STORE_CONNECT_KEY_IDENTIFIER",
        "APP_STORE_CONNECT_PRIVATE_KEY",
    ):
        required(name)
    validate_app_record()
    keychain = str(target / "signing.keychain-db")
    run(
        "keychain",
        "initialize",
        "--path",
        keychain,
        "--password",
        "@env:IOS_TEMP_KEYCHAIN_PASSWORD",
        "--timeout",
        "3600",
    )
    if os.environ.get("IOS_SIGNING_MODE", "automatic") == "automatic":
        required("CERTIFICATE_PRIVATE_KEY")
        run(
            "app-store-connect",
            "fetch-signing-files",
            required("IOS_BUNDLE_ID"),
            "--type",
            "IOS_APP_STORE",
            "--strict-match-identifier",
            "--create",
            "--silent",
            "--private-key",
            "@env:APP_STORE_CONNECT_PRIVATE_KEY",
            "--certificate-key",
            "@env:CERTIFICATE_PRIVATE_KEY",
            "--certificates-dir",
            str(certificate_dir),
            "--profiles-dir",
            str(profile_dir),
        )
        os.environ["IOS_IMPORT_PASSWORD"] = ""
    else:
        for env_name, path in (
            ("IOS_DISTRIBUTION_P12_BASE64", certificate_dir / "distribution.p12"),
            ("IOS_PROFILE_BASE64", profile_dir / "app.mobileprovision"),
        ):
            path.write_bytes(base64.b64decode(required(env_name), validate=True))
            path.chmod(0o600)
        os.environ["IOS_IMPORT_PASSWORD"] = os.environ.get(
            "IOS_DISTRIBUTION_P12_PASSWORD", ""
        )
    profiles = list(profile_dir.glob("*.mobileprovision"))
    if not profiles:
        raise ValueError("No App Store provisioning profile was obtained")
    # Validate before using any profile, and record only filenames for cleanup.
    installed = []
    destination = Path.home() / "Library/MobileDevice/Provisioning Profiles"
    destination.mkdir(parents=True, exist_ok=True)
    for path in profiles:
        profile = read_profile(path)
        validate_profile(profile, dict(os.environ))
        name = f"{profile['UUID']}.mobileprovision"
        shutil.copyfile(path, destination / name)
        installed.append(name)
        (target / "installed.json").write_text(json.dumps(installed), encoding="utf-8")
    if not list(certificate_dir.glob("*.p12")):
        raise ValueError("No signing certificate with a private key was obtained")
    run(
        "keychain",
        "add-certificates",
        "--path",
        keychain,
        "--certificate",
        str(certificate_dir / "*.p12"),
        "--certificate-password",
        "@env:IOS_IMPORT_PASSWORD",
    )
    configure_release_identity(
        MOBILE / "ios/Runner.xcodeproj/project.pbxproj", required("IOS_BUNDLE_ID")
    )
    run(
        "xcode-project",
        "use-profiles",
        "--project",
        "ios/Runner.xcodeproj",
        "--profile",
        str(profile_dir / "*.mobileprovision"),
        "--export-options-plist",
        str(target / "ExportOptions.plist"),
        "--custom-export-options",
        json.dumps(
            {
                "testFlightInternalTestingOnly": True,
                "manageAppVersionAndBuildNumber": False,
            }
        ),
    )


def build() -> None:
    validate_config(dict(os.environ))
    options = signing_dir() / "ExportOptions.plist"
    if not options.is_file():
        raise ValueError("Signing setup must succeed before building")
    run(
        "flutter",
        "build",
        "ipa",
        "--release",
        f"--export-options-plist={options}",
        f"--build-name={required('APP_VERSION')}",
        f"--build-number={required('BUILD_NUMBER')}",
        f"--dart-define=APP_VERSION={required('APP_VERSION')}",
        f"--dart-define=BUILD_NUMBER={required('BUILD_NUMBER')}",
        "--dart-define=APP_ENV=staging",
        f"--dart-define=API_BASE_URL={required('API_BASE_URL')}",
    )


def ipa_path() -> Path:
    files = list((MOBILE / "build/ios/ipa").glob("*.ipa"))
    if len(files) != 1:
        raise ValueError(
            "Expected exactly one signed IPA; unsigned Runner.app is not an IPA"
        )
    return files[0]


def verify() -> None:
    ipa = ipa_path()
    extracted = signing_dir() / "verify"
    run("ditto", "-x", "-k", str(ipa), str(extracted))
    apps = list((extracted / "Payload").glob("*.app"))
    if len(apps) != 1:
        raise ValueError("IPA must contain exactly one app")
    app = apps[0]
    run("codesign", "--verify", "--deep", "--strict", str(app))
    info = plistlib.loads((app / "Info.plist").read_bytes())
    for name, expected in {
        "CFBundleIdentifier": required("IOS_BUNDLE_ID"),
        "CFBundleDisplayName": required("APP_DISPLAY_NAME"),
        "CFBundleShortVersionString": required("APP_VERSION"),
        "CFBundleVersion": required("BUILD_NUMBER"),
    }.items():
        if info.get(name) != expected:
            raise ValueError(f"Signed IPA identity mismatch: {name}")
    if float(info.get("MinimumOSVersion", "0")) < 16:
        raise ValueError("Signed IPA must target iOS 16 or later")
    profile = read_profile(app / "embedded.mobileprovision")
    validate_profile(profile, dict(os.environ))
    entitlements = plistlib.loads(
        run("codesign", "-d", "--entitlements", ":-", str(app), capture=True)
    )
    if (
        entitlements.get("com.apple.developer.healthkit") is not True
        or entitlements.get("com.apple.developer.team-identifier")
        != required("IOS_TEAM_ID")
        or entitlements.get("get-task-allow", False)
    ):
        raise ValueError(
            "Signed app entitlements do not match distribution requirements"
        )
    evidence = {
        "commit_sha": required("GITHUB_SHA"),
        "run_id": required("GITHUB_RUN_ID"),
        "run_attempt": required("GITHUB_RUN_ATTEMPT"),
        "ipa_sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
        "bundle_id": info["CFBundleIdentifier"],
        "app_version": info["CFBundleShortVersionString"],
        "build_number": info["CFBundleVersion"],
        "signed_ipa_verified": True,
        "healthkit_entitlement": True,
        "testflight_uploaded": False,
        "testflight_processed": False,
        "physical_iphone_accepted": False,
    }
    (ipa.parent / "release-evidence.json").write_text(
        json.dumps(evidence, indent=2), encoding="utf-8"
    )
    print(
        "Signed IPA signature, identity, HealthKit profile and native build number verified"
    )


def upload() -> None:
    for name in (
        "APP_STORE_CONNECT_ISSUER_ID",
        "APP_STORE_CONNECT_KEY_IDENTIFIER",
        "APP_STORE_CONNECT_PRIVATE_KEY",
    ):
        required(name)
    ipa = ipa_path()
    path = ipa.parent / "release-evidence.json"
    evidence = json.loads(path.read_text(encoding="utf-8"))
    if (
        evidence.get("signed_ipa_verified") is not True
        or evidence.get("ipa_sha256") != hashlib.sha256(ipa.read_bytes()).hexdigest()
    ):
        raise ValueError("Only the verified signed IPA may be uploaded")
    # No --testflight (external beta review), --app-store, or broad beta-group distribution.
    # The owner selects the processed build in their one-person internal group.
    run(
        "app-store-connect",
        "publish",
        "--path",
        str(ipa),
        "--silent",
        "--enable-package-validation",
        "--private-key",
        "@env:APP_STORE_CONNECT_PRIVATE_KEY",
    )
    evidence["testflight_uploaded"] = True
    evidence["upload_completed_at"] = dt.datetime.now(dt.UTC).isoformat()
    path.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print(
        "Upload command completed. Apple processing and owner-only group assignment still require verification"
    )


def cleanup() -> None:
    target = signing_dir()
    if not target.exists():
        return
    keychain = target / "signing.keychain-db"
    if keychain.exists():
        run("security", "delete-keychain", str(keychain))
    manifest = target / "installed.json"
    if manifest.exists():
        for name in json.loads(manifest.read_text(encoding="utf-8")):
            if not re.fullmatch(r"[A-Fa-f0-9-]{36}\.mobileprovision", name):
                raise ValueError("Refusing invalid profile cleanup target")
            (Path.home() / "Library/MobileDevice/Provisioning Profiles" / name).unlink(
                missing_ok=True
            )
    shutil.rmtree(target)  # Exact dedicated child of RUNNER_TEMP was validated above.


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "phase", choices=("preflight", "sign", "build", "verify", "upload", "cleanup")
    )
    args = parser.parse_args()
    try:
        globals()[args.phase]()
    except (ValueError, subprocess.CalledProcessError, OSError) as error:
        # Never print subprocess argv/output or exception payloads from Apple.
        message = str(error) if isinstance(error, ValueError) else type(error).__name__
        print(f"iOS release phase {args.phase} failed: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
