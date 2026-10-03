"""Signing guardrails are testable without a Mac or Apple credentials."""

import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "ios_release", Path(__file__).parents[1] / "ios_release.py"
)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)

CONFIG = {
    "IOS_TEAM_ID": "AB12345678",
    "IOS_BUNDLE_ID": "org.health.owner",
    "APP_DISPLAY_NAME": "私人健康",
    "ASC_APP_ID": "1234567890",
    "API_BASE_URL": "https://health.owner.test/api/v1",
    "APP_ENV": "staging",
    "APP_VERSION": "0.1.0",
    "BUILD_NUMBER": "21.1",
    "IOS_SIGNING_MODE": "automatic",
}


def profile():
    return {
        "TeamIdentifier": [CONFIG["IOS_TEAM_ID"]],
        "ApplicationIdentifierPrefix": [CONFIG["IOS_TEAM_ID"]],
        "UUID": "12345678-1234-1234-1234-123456789abc",
        "ExpirationDate": dt.datetime.now(dt.UTC) + dt.timedelta(days=30),
        "Entitlements": {
            "application-identifier": "AB12345678.org.health.owner",
            "com.apple.developer.healthkit": True,
            "get-task-allow": False,
        },
    }


class ReleaseGuardrailsTest(unittest.TestCase):
    def test_valid_owner_configuration(self):
        release.validate_config(CONFIG)

    def test_signing_identity_resolves_all_runner_configs_not_tests(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary) / "project.pbxproj"
            marker = 'PRODUCT_BUNDLE_IDENTIFIER = "$(IOS_BUNDLE_ID)";'
            project.write_text(
                "\n".join(
                    [marker] * 3
                    + ["PRODUCT_BUNDLE_IDENTIFIER = org.fixture.RunnerTests;"]
                )
            )
            release.configure_release_identity(project, CONFIG["IOS_BUNDLE_ID"])
            output = project.read_text()
            self.assertEqual(
                output.count('PRODUCT_BUNDLE_IDENTIFIER = "org.health.owner";'), 3
            )
            self.assertIn("org.fixture.RunnerTests", output)

    def test_app_record_is_checked_before_signing(self):
        with (
            patch.dict(os.environ, CONFIG),
            patch.object(
                release,
                "run",
                return_value=json.dumps(
                    {
                        "id": CONFIG["ASC_APP_ID"],
                        "attributes": {"bundleId": CONFIG["IOS_BUNDLE_ID"]},
                    }
                ).encode(),
            ) as command,
        ):
            release.validate_app_record()
        self.assertEqual(
            command.call_args.args[:3], ("app-store-connect", "apps", "get")
        )
        with (
            patch.dict(os.environ, CONFIG),
            patch.object(
                release,
                "run",
                return_value=json.dumps(
                    {
                        "id": CONFIG["ASC_APP_ID"],
                        "attributes": {"bundleId": "wrong.bundle"},
                    }
                ).encode(),
            ),
            self.assertRaises(ValueError),
        ):
            release.validate_app_record()

    def test_missing_apple_metadata_cannot_fall_back(self):
        for field in ("IOS_TEAM_ID", "IOS_BUNDLE_ID", "APP_DISPLAY_NAME", "ASC_APP_ID"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                release.validate_config({**CONFIG, field: ""})

    def test_placeholder_or_secret_bearing_api_is_rejected(self):
        for url in (
            "http://health.owner.test/api/v1",
            "https://localhost/api/v1",
            "https://staging-api.personal-health.invalid/api/v1",
            "https://example.com/api/v1",
            "https://user:password@health.owner.test/api/v1",
            "https://health.owner.test/api/v1?key=secret",
            "https://health.owner.test/",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                release.validate_config({**CONFIG, "API_BASE_URL": url})

    def test_apple_version_not_flutter_beta_semver(self):
        for version in ("0.1.0-beta.1", "", "1.a.0"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.validate_config({**CONFIG, "APP_VERSION": version})

    def test_build_number_limits(self):
        for number in ("37135036631.1", "1.100", "0", "1-beta"):
            with self.subTest(number=number), self.assertRaises(ValueError):
                release.validate_config({**CONFIG, "BUILD_NUMBER": number})

    def test_app_store_healthkit_profile(self):
        release.validate_profile(profile(), CONFIG)

    def test_distribution_identity_and_entitlement_required(self):
        invalid = [
            {**profile(), "TeamIdentifier": ["OTHERTEAM0"]},
            {**profile(), "Entitlements": {"application-identifier": "AB12345678.*"}},
            {
                **profile(),
                "Entitlements": {
                    "application-identifier": "AB12345678.org.health.owner"
                },
            },
            {**profile(), "ProvisionedDevices": ["device-id"]},
            {**profile(), "ProvisionsAllDevices": True},
            {**profile(), "ExpirationDate": dt.datetime(2020, 1, 1, tzinfo=dt.UTC)},
            {**profile(), "UUID": "../escape"},
        ]
        for value in invalid:
            with self.subTest(profile=value), self.assertRaises(ValueError):
                release.validate_profile(value, CONFIG)

    def test_cleanup_cannot_delete_workspace_or_runner_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            for target in (
                temporary,
                str(Path(temporary) / "other"),
                str(Path(temporary).parent),
            ):
                with (
                    self.subTest(target=target),
                    patch.dict(
                        os.environ,
                        {
                            "RUNNER_TEMP": temporary,
                            "SIGNING_DIR": target,
                        },
                    ),
                    self.assertRaises(ValueError),
                ):
                    release.signing_dir()

    def test_actual_ipa_command_and_matching_debug_version(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "health-ios-signing"
            target.mkdir()
            (target / "ExportOptions.plist").write_bytes(b"test-options")
            with (
                patch.dict(
                    os.environ,
                    {**CONFIG, "RUNNER_TEMP": temporary, "SIGNING_DIR": str(target)},
                ),
                patch.object(release, "run") as command,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                release.build()
            args = command.call_args.args
            self.assertEqual(args[:4], ("flutter", "build", "ipa", "--release"))
            self.assertNotIn("--no-codesign", args)
            self.assertIn("--build-number=21.1", args)
            self.assertIn("--dart-define=BUILD_NUMBER=21.1", args)
            self.assertIn("--dart-define=APP_VERSION=0.1.0", args)

    def test_upload_never_submits_external_beta_or_app_store_review(self):
        with tempfile.TemporaryDirectory() as temporary:
            ipa = Path(temporary) / "owner.ipa"
            ipa.write_bytes(b"signed-test-fixture")
            (ipa.parent / "release-evidence.json").write_text(
                json.dumps(
                    {
                        "signed_ipa_verified": True,
                        "ipa_sha256": release.hashlib.sha256(
                            ipa.read_bytes()
                        ).hexdigest(),
                        "testflight_processed": False,
                    }
                ),
                encoding="utf-8",
            )
            with (
                patch.dict(
                    os.environ,
                    {
                        "APP_STORE_CONNECT_ISSUER_ID": "issuer",
                        "APP_STORE_CONNECT_KEY_IDENTIFIER": "key-id",
                        "APP_STORE_CONNECT_PRIVATE_KEY": "sensitive-test-value",
                    },
                ),
                patch.object(release, "ipa_path", return_value=ipa),
                patch.object(release, "run") as command,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                release.upload()
            args = command.call_args.args
            self.assertNotIn("sensitive-test-value", args)
            self.assertNotIn("--testflight", args)
            self.assertNotIn("--app-store", args)
            self.assertNotIn("--beta-group", args)
            self.assertIn("--enable-package-validation", args)
            evidence = json.loads((ipa.parent / "release-evidence.json").read_text())
            self.assertTrue(evidence["testflight_uploaded"])
            self.assertFalse(evidence["testflight_processed"])


if __name__ == "__main__":
    unittest.main()
