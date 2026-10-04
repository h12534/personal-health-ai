"""Unsigned artifact guardrails; no Apple account, Mac, or health data needed."""

import contextlib
import importlib.util
import io
import os
import plistlib
import stat
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location(
    "personal_sideload", ROOT / "scripts/personal_sideload.py"
)
sideload = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sideload)
SHA = "1" * 40


def fixture(directory, variant="healthkit", platform=2, signed=False):
    app = Path(directory) / "Runner.app"
    app.mkdir()
    config = sideload.configuration(variant)
    info = {
        "CFBundleIdentifier": "com.personal.healthcoach",
        "CFBundleDisplayName": "私人健康",
        "CFBundleExecutable": "Runner",
        "CFBundleShortVersionString": config["APP_VERSION"],
        "CFBundleVersion": config["BUILD_NUMBER"],
        "MinimumOSVersion": "16.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "AppDistribution": "personal_sideload",
        "PersonalSideloadFree": config["PERSONAL_SIDELOAD_FREE"],
    }
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    commands = struct.pack("<6I", 0x32, 24, platform, 0x100000, 0x100000, 0)
    if signed:
        commands += struct.pack("<4I", 0x1D, 16, 0, 0)
    executable = app / "Runner"
    executable.write_bytes(
        struct.pack(
            "<8I", 0xFEEDFACF, 0x100000C, 0, 2, 2 if signed else 1, len(commands), 0, 0
        )
        + commands
    )
    executable.chmod(0o755)
    return app, config


class PersonalSideloadTest(unittest.TestCase):
    def package(self, directory, app, config, variant="healthkit"):
        with contextlib.redirect_stdout(io.StringIO()):
            return sideload.package(
                app,
                Path(directory) / "artifact",
                variant,
                config,
                SHA,
                {"com.apple.developer.healthkit": True}
                if variant == "healthkit"
                else {},
            )

    def test_standard_payload_metadata_hash_and_executable_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            app, config = fixture(directory)
            evidence = self.package(directory, app, config)
            ipa = Path(directory) / "artifact" / evidence["artifact"]
            with zipfile.ZipFile(ipa) as archive:
                self.assertIn("Payload/Runner.app/Info.plist", archive.namelist())
                mode = archive.getinfo("Payload/Runner.app/Runner").external_attr >> 16
                self.assertTrue(mode & stat.S_IXUSR)
                self.assertFalse(
                    any("mobileprovision" in name for name in archive.namelist())
                )
            self.assertEqual(
                evidence["sha256"],
                sideload.hashlib.sha256(ipa.read_bytes()).hexdigest(),
            )
            self.assertEqual(evidence["commit_sha"], SHA)
            self.assertFalse(evidence["api_configured"])
            self.assertEqual(evidence["iphone_launch"], "NOT_RUN")
            self.assertEqual(evidence["signed_entitlements"], "NONE_IN_UNSIGNED_RUNNER")

    def test_free_flavor_has_no_healthkit_or_remote_push_request(self):
        with tempfile.TemporaryDirectory() as directory:
            app, config = fixture(directory, "free")
            evidence = self.package(directory, app, config, "free")
            self.assertEqual(evidence["flavor"], "PERSONAL_SIDELOAD_FREE")
            self.assertEqual(evidence["requested_entitlements"], {})
            self.assertFalse(evidence["remote_push_enabled"])

    def test_stale_native_flavor_or_version_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            app, config = fixture(directory)
            with self.assertRaisesRegex(ValueError, "metadata mismatch"):
                self.package(directory, app, {**config, "BUILD_NUMBER": "9"})

    def test_simulator_binary_is_rejected_even_if_plist_says_device(self):
        with tempfile.TemporaryDirectory() as directory:
            app, config = fixture(directory, platform=7)
            with self.assertRaisesRegex(ValueError, "device platform"):
                self.package(directory, app, config)

    def test_signed_binary_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            app, config = fixture(directory, signed=True)
            with self.assertRaisesRegex(ValueError, "LC_CODE_SIGNATURE"):
                self.package(directory, app, config)

    def test_profile_or_key_cannot_enter_unsigned_artifact(self):
        for name in ("embedded.mobileprovision", "apple.p8"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                app, config = fixture(directory)
                (app / name).write_bytes(b"synthetic forbidden artifact")
                with self.assertRaisesRegex(ValueError, "Signing material"):
                    self.package(directory, app, config)

    def test_secret_bearing_api_and_invalid_build_are_rejected(self):
        for values in (
            {"API_BASE_URL": "https://user:password@health.example/api/v1"},
            {"API_BASE_URL": "https://health.example/api/v1?token=value"},
            {"BUILD_NUMBER": "10000.1"},
        ):
            with (
                self.subTest(values=values),
                patch.dict(os.environ, values),
                self.assertRaises(ValueError),
            ):
                sideload.configuration("free")

    def test_build_configures_matching_native_and_dart_mode_without_signing(self):
        with patch.object(sideload.subprocess, "run") as command:
            sideload.build("free")
        calls = command.call_args_list
        self.assertEqual(calls[0].args[0], ["dart", "run", "tool/configure_ios.dart"])
        args = calls[1].args[0]
        self.assertEqual(
            args[:5], ["flutter", "build", "ios", "--release", "--no-codesign"]
        )
        self.assertIn("--dart-define=PERSONAL_SIDELOAD_FREE=true", args)
        self.assertEqual(calls[0].kwargs["env"]["PERSONAL_SIDELOAD_FREE"], "true")

    def test_original_healthkit_and_secure_storage_remain(self):
        original = plistlib.loads(
            (ROOT / "mobile/ios/Runner/Runner.entitlements").read_bytes()
        )
        free = plistlib.loads(
            (ROOT / "mobile/ios/Runner/PersonalSideloadFree.entitlements").read_bytes()
        )
        self.assertTrue(original["com.apple.developer.healthkit"])
        self.assertEqual(free, {})
        storage = (ROOT / "mobile/lib/core/network/api_client.dart").read_text(
            encoding="utf-8"
        )
        self.assertIn("SecureTokenStore(ref.watch(secureStorageProvider))", storage)
        self.assertIn("first_unlock_this_device", storage)

    def test_five_original_ci_jobs_remain_and_personal_job_has_no_secrets(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        for job in (
            "release-audit",
            "backend",
            "backend-postgres",
            "mobile-ios-primary",
            "mobile-android-compat",
        ):
            self.assertIn(f"  {job}:\n", workflow)
        personal = workflow.split("  mobile-ios-personal-sideload:\n", 1)[1].split(
            "  mobile-ios-signed:\n", 1
        )[0]
        for forbidden in (
            "secrets.",
            "IOS_TEAM_ID",
            "APP_STORE_CONNECT",
            "keychain",
            "fetch-signing-files",
        ):
            self.assertNotIn(forbidden, personal)
        self.assertIn("--variant healthkit", personal)
        self.assertIn("--variant free", personal)
        self.assertIn("vars.APP_DISTRIBUTION == 'app_store'", workflow)


if __name__ == "__main__":
    unittest.main()
