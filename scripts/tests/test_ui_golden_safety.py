import hashlib
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

from scripts.ui_golden_safety import (
    PNG_SIGNATURE,
    SafetyFailure,
    check_ocr_text,
    prepare_export,
    sanitize_png,
    verify_context,
    verify_sources,
)


def chunk(kind, payload=b""):
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def png(extra=b""):
    header = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    return (
        PNG_SIGNATURE
        + chunk(b"IHDR", header)
        + extra
        + chunk(b"IDAT", zlib.compress(b"\x00\x12\x34\x56\xff"))
        + chunk(b"IEND")
    )


class UiGoldenSafetyTests(unittest.TestCase):
    def test_pixels_unchanged_and_ancillary_removed(self):
        original = png()
        self.assertEqual(sanitize_png(original, (1, 1)), original)
        self.assertEqual(sanitize_png(png(chunk(b"sRGB", b"\0")), (1, 1)), original)

    def test_all_private_metadata_blocks_not_silent_redaction(self):
        for kind in (b"eXIf", b"tEXt", b"zTXt", b"iTXt"):
            with self.subTest(kind=kind), self.assertRaises(SafetyFailure):
                sanitize_png(png(chunk(kind, b"private")), (1, 1))

    def test_macos_full_precision_chunk_is_validated_and_stripped(self):
        self.assertEqual(sanitize_png(png(chunk(b"sBIT", b"\x08" * 4)), (1, 1)), png())
        for payload in (b"", b"\x08" * 3, b"\x07" * 4, b"private"):
            with self.subTest(payload=payload), self.assertRaises(SafetyFailure):
                sanitize_png(png(chunk(b"sBIT", payload)), (1, 1))
        with self.assertRaises(SafetyFailure):
            sanitize_png(png(chunk(b"sBIT", b"\x08" * 4) * 2), (1, 1))

    def test_unrecognized_chunk_still_blocks(self):
        with self.assertRaisesRegex(SafetyFailure, "UNAPPROVED_PNG_CHUNK"):
            sanitize_png(png(chunk(b"iCCP", b"unreviewed profile")), (1, 1))

    def test_corruption_trailer_and_wrong_dimensions_block(self):
        for data, size in (
            (png()[:-2], (1, 1)),
            (png() + b"extra", (1, 1)),
            (png(), (2, 1)),
        ):
            with self.subTest(size=size), self.assertRaises(SafetyFailure):
                sanitize_png(data, size)
        changed = bytearray(png())
        changed[29] ^= 1
        with self.assertRaises(SafetyFailure):
            sanitize_png(bytes(changed), (1, 1))

    def test_email_token_path_device_id_phone_block(self):
        samples = [
            "person@example.invalid",
            "sk-syntheticsecret123",
            "Token: fictional-value",
            "/Users/sample/private",
            "12345678-1234-1234-1234-123456789012",
            "13800000000",
        ]
        for text in samples:
            with self.subTest(text=text), self.assertRaises(SafetyFailure):
                check_ocr_text([text])

    def test_diagnostic_reason_never_echoes_recognized_content(self):
        with self.assertRaisesRegex(SafetyFailure, "^PRIVATE_CONTENT_EMAIL$"):
            check_ocr_text(["person@example.invalid"])

    def test_https_is_not_a_windows_drive_but_local_paths_still_block(self):
        check_ocr_text(["https://docs.example.invalid/health/context"])
        for text in ("C:/private", "D:\\private", "saved C:/private", "/Users/sample"):
            with (
                self.subTest(text=text),
                self.assertRaisesRegex(SafetyFailure, "PRIVATE_CONTENT_PATH"),
            ):
                check_ocr_text([text])
        with self.assertRaisesRegex(SafetyFailure, "NON_SYNTHETIC_URL"):
            check_ocr_text(["https://private.example/health"])

    def test_frozen_synthetic_date_axis_is_not_a_phone(self):
        capture = "health-variant-clinical.png"
        check_ocr_text(["202661 202691"], capture)
        check_ocr_text(["20260601 20260901"], capture)
        for text, name in (
            ("202661 202691", "unreviewed.png"),
            ("13800000000", capture),
            ("Phone: 202661 202691", capture),
            ("202661 202691 13800000000", capture),
            ("202661 202692", capture),
            ("202661 202691 person@example.invalid", capture),
        ):
            with self.subTest(text=text, name=name), self.assertRaises(SafetyFailure):
                check_ocr_text([text], name)

    def test_legitimate_labels_and_synthetic_values_do_not_claim_identity(self):
        check_ocr_text(
            [
                "邮箱",
                "密码",
                "糖化血红蛋白",
                "5.8 %",
                "2026年9月1日",
                "未启用 Apple Health 自动同步",
            ]
        )

    def test_missing_ocr_and_private_url_block(self):
        for values in ([], [""], ["https://private.example/health"]):
            with self.assertRaises(SafetyFailure):
                check_ocr_text(values)

    def test_sealed_source_drift_blocks_with_crlf_normalization(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "fixture.dart"
            source.write_bytes(b"synthetic\r\n")
            policy = {
                "sources": {"fixture.dart": hashlib.sha256(b"synthetic\n").hexdigest()}
            }
            verify_sources(root, policy)
            source.write_bytes(b"changed")
            with self.assertRaises(SafetyFailure):
                verify_sources(root, policy)

    def test_forks_wrong_branch_or_non_dispatch_block(self):
        policy = {
            "repository": "h12534/personal-health-ai",
            "ref": "refs/heads/feature/ui-redesign-impeccable",
        }
        env = {
            "GITHUB_ACTIONS": "true",
            "GITHUB_REPOSITORY": policy["repository"],
            "GITHUB_REF": policy["ref"],
            "GITHUB_EVENT_NAME": "workflow_dispatch",
        }
        with mock.patch.dict("os.environ", env, clear=True):
            verify_context(policy)
        for key in env:
            with (
                mock.patch.dict("os.environ", {**env, key: "wrong"}, clear=True),
                self.assertRaises(SafetyFailure),
            ):
                verify_context(policy)

    def test_export_never_publishes_a_partial_set(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            source.mkdir()
            for name in ("a.png", "b.png"):
                (source / name).write_bytes(png())
            output = root / "approved"
            with (
                mock.patch(
                    "scripts.ui_golden_safety.local_ocr",
                    side_effect=[["合成记录"], ["person@example.invalid"]],
                ),
                self.assertRaises(SafetyFailure),
            ):
                prepare_export(
                    source, output, {"a.png": [1, 1], "b.png": [1, 1]}, Path("ocr")
                )
            self.assertFalse(output.exists())
            with mock.patch(
                "scripts.ui_golden_safety.local_ocr", return_value=["合成记录"]
            ):
                self.assertEqual(
                    prepare_export(
                        source, output, {"a.png": [1, 1], "b.png": [1, 1]}, Path("ocr")
                    ),
                    2,
                )
            self.assertEqual(
                sorted(file.name for file in output.iterdir()), ["a.png", "b.png"]
            )

    def test_unknown_files_block_even_if_not_selected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            source.mkdir()
            (source / "a.png").write_bytes(png())
            (source / "debug.log").write_text("not allowed")
            with self.assertRaises(SafetyFailure):
                prepare_export(
                    source, root / "approved", {"a.png": [1, 1]}, Path("ocr")
                )
