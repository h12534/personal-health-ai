"""Fail-closed boundary: sealed synthetic fixtures, local OCR, PNGs only.

Suspicious content blocks the entire export; pixels are never painted over.
Ancillary chunks are stripped while IHDR/IDAT compressed pixel bytes stay exact.
No screenshots, recognized text, raw errors, paths or logs are Git baselines.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import unicodedata
import zlib
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PRIVATE_CHUNKS = {b"eXIf", b"tEXt", b"zTXt", b"iTXt"}
SAFE_ANCILLARY = {b"sRGB", b"gAMA", b"cHRM", b"pHYs"}
PRIVATE_PATTERNS = (
    r"@",
    r"(?i)(?:sk[-_]|ghp_|github_pat_|AKIA)[a-z0-9_\-]{8,}",
    r"(?i)bearer\s+\S+|-----BEGIN|eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+",
    r"(?i)(?:token|api\s*key|password|密码|令牌)\s*[:=]\s*\S+",
    r"(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
    r"(?i)/Users/|/home/|[a-z]:[\\/]|file://|127\.0\.0\.1",
    r"(?<!\d)(?:\+?\d[ -]?){11,}(?!\d)",
    r"[A-Za-z0-9_+/=-]{40,}",
)


class SafetyFailure(Exception):
    """Only fixed reason codes can appear in public logs."""


def verify_sources(root: Path, policy: dict) -> None:
    for relative, expected in policy["sources"].items():
        source = root / relative
        if source.is_symlink() or not source.is_file():
            raise SafetyFailure("SOURCE_MISSING_OR_LINKED")
        content = source.read_bytes()
        if source.suffix in {".dart", ".py", ".swift", ".yaml", ".lock"}:
            content = content.replace(b"\r\n", b"\n")
        if hashlib.sha256(content).hexdigest() != expected:
            raise SafetyFailure("SOURCE_ATTESTATION_CHANGED")


def verify_context(policy: dict) -> None:
    if (
        os.environ.get("GITHUB_ACTIONS") != "true"
        or os.environ.get("GITHUB_REPOSITORY") != policy["repository"]
        or os.environ.get("GITHUB_REF") != policy["ref"]
        or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
    ):
        raise SafetyFailure("UNAUTHORIZED_CAPTURE_CONTEXT")


def sanitize_png(data: bytes, size: tuple[int, int]) -> bytes:
    if not data.startswith(PNG_SIGNATURE) or len(data) > 8_000_000:
        raise SafetyFailure("INVALID_PNG")
    offset = 8
    kept = bytearray(PNG_SIGNATURE)
    types: list[bytes] = []
    compressed = bytearray()
    channels = 0
    while offset < len(data):
        if offset + 12 > len(data):
            raise SafetyFailure("TRUNCATED_PNG")
        length, kind = struct.unpack_from(">I4s", data, offset)
        end = offset + 12 + length
        if end > len(data):
            raise SafetyFailure("INVALID_CHUNK_SIZE")
        payload = data[offset + 8 : end - 4]
        crc = struct.unpack_from(">I", data, end - 4)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != crc:
            raise SafetyFailure("INVALID_CHUNK_CRC")
        if kind in PRIVATE_CHUNKS:
            raise SafetyFailure("PRIVATE_PNG_METADATA")
        if kind == b"IHDR":
            if types or len(payload) != 13:
                raise SafetyFailure("INVALID_HEADER")
            width, height, depth, color, compression, filtering, interlace = (
                struct.unpack(">IIBBBBB", payload)
            )
            if (width, height) != size or depth != 8 or color not in (2, 6):
                raise SafetyFailure("UNEXPECTED_IMAGE_SHAPE")
            if (compression, filtering, interlace) != (0, 0, 0):
                raise SafetyFailure("UNSUPPORTED_PNG_ENCODING")
            channels = 3 if color == 2 else 4
        elif kind == b"IDAT":
            if not types or b"IEND" in types:
                raise SafetyFailure("INVALID_IMAGE_DATA_ORDER")
            compressed.extend(payload)
        elif kind == b"IEND":
            if payload or end != len(data) or b"IDAT" not in types:
                raise SafetyFailure("INVALID_PNG_END")
        elif kind not in SAFE_ANCILLARY:
            raise SafetyFailure("UNAPPROVED_PNG_CHUNK")
        if kind in {b"IHDR", b"IDAT", b"IEND"}:
            kept.extend(data[offset:end])
        types.append(kind)
        offset = end
    if not types or types[0] != b"IHDR" or types[-1] != b"IEND":
        raise SafetyFailure("INCOMPLETE_PNG")
    row_size = size[0] * channels + 1
    expected_size = size[1] * row_size
    decoder = zlib.decompressobj()
    try:
        pixels = decoder.decompress(compressed, expected_size + 1)
    except zlib.error as error:
        raise SafetyFailure("INVALID_COMPRESSED_PIXELS") from error
    if (
        len(pixels) != expected_size
        or not decoder.eof
        or decoder.unused_data
        or decoder.unconsumed_tail
        or any(pixels[row] > 4 for row in range(0, len(pixels), row_size))
    ):
        raise SafetyFailure("INVALID_PIXEL_DATA")
    return bytes(kept)


def check_ocr_text(texts: list[str]) -> None:
    if not texts or not all(isinstance(text, str) and text.strip() for text in texts):
        raise SafetyFailure("OCR_INCOMPLETE")
    normalized = unicodedata.normalize("NFKC", "\n".join(texts))
    if any(re.search(pattern, normalized) for pattern in PRIVATE_PATTERNS):
        raise SafetyFailure("PRIVATE_CONTENT_DETECTED")
    for url in re.findall(r"https?://[^\s]+", normalized):
        if not url.startswith("https://docs.example.invalid/"):
            raise SafetyFailure("NON_SYNTHETIC_URL")


def local_ocr(executable: Path, image: Path) -> list[str]:
    try:
        result = subprocess.run(
            [str(executable), str(image)], capture_output=True, timeout=60, check=False
        )
        if result.returncode != 0:
            raise SafetyFailure("OCR_UNAVAILABLE")
        texts = json.loads(result.stdout)
        if not isinstance(texts, list):
            raise SafetyFailure("OCR_INVALID_RESPONSE")
        return texts
    except (OSError, subprocess.TimeoutExpired, ValueError) as error:
        raise SafetyFailure("OCR_UNAVAILABLE") from error


def prepare_export(
    source: Path, output: Path, captures: dict, ocr_executable: Path
) -> int:
    if source.is_symlink() or not source.is_dir() or output.exists():
        raise SafetyFailure("UNSAFE_EXPORT_DIRECTORY")
    files = list(source.iterdir())
    if {file.name for file in files} != set(captures):
        raise SafetyFailure("MISSING_OR_UNEXPECTED_FILES")
    if any(file.is_symlink() or not file.is_file() for file in files):
        raise SafetyFailure("NON_REGULAR_CAPTURE")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ui-safe-stage-", dir=output.parent) as tmp:
        staging = Path(tmp)
        for file in sorted(files):
            destination = staging / file.name
            destination.write_bytes(
                sanitize_png(file.read_bytes(), tuple(captures[file.name]))
            )
            check_ocr_text(local_ocr(ocr_executable, destination))
        staging.rename(output)
    return len(files)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("attest", "prepare"))
    parser.add_argument("--flavor", choices=("standard", "free"))
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--ocr", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        policy = json.loads(
            (root / "scripts/ui_golden_policy.json").read_text(encoding="utf-8")
        )
        verify_context(policy)
        verify_sources(root, policy)
        if args.command == "prepare":
            if not all((args.flavor, args.input, args.output, args.ocr)):
                raise SafetyFailure("INCOMPLETE_EXPORT_ARGUMENTS")
            expected_input = root / "mobile/test/failures/ui-review" / args.flavor
            expected_output = root / "mobile/build/ui-review" / args.flavor
            if (
                args.input.resolve() != expected_input
                or args.output.resolve() != expected_output
            ):
                raise SafetyFailure("OUT_OF_SCOPE_EXPORT_PATH")
            count = prepare_export(
                args.input, args.output, policy["captures"][args.flavor], args.ocr
            )
            print(f"synthetic_ui_safety=passed images={count} metadata=none ocr=local")
        else:
            print("synthetic_ui_source_attestation=passed network=forbidden")
        return 0
    except (SafetyFailure, OSError, ValueError, KeyError, struct.error) as error:
        code = str(error) if isinstance(error, SafetyFailure) else "CHECK_UNAVAILABLE"
        print(f"synthetic_ui_safety=blocked reason={code}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
