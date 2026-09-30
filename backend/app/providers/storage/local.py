import asyncio
from pathlib import Path, PurePosixPath
from uuid import uuid4

from app.core.errors import AppError


class LocalStorageProvider:
    def __init__(self, root: str | Path) -> None:
        self.root = Path(root).resolve()

    def _resolve(self, object_key: str) -> Path:
        relative = PurePosixPath(object_key)
        if relative.is_absolute() or ".." in relative.parts:
            raise AppError("invalid_object_key", "Storage object key is invalid.", 400)
        target = (self.root / Path(*relative.parts)).resolve()
        if target != self.root and self.root not in target.parents:
            raise AppError("invalid_object_key", "Storage object key is invalid.", 400)
        return target

    async def put_private(
        self, data: bytes, content_type: str, suffix: str, prefix: str = ""
    ) -> str:
        del content_type
        clean_suffix = suffix.lower().lstrip(".")
        if clean_suffix not in {"jpg", "jpeg", "png", "webp", "pdf", "txt", "md", "html"}:
            raise AppError("invalid_file_suffix", "Private file suffix is not supported.", 422)
        clean_prefix = "/".join(
            part for part in PurePosixPath(prefix).parts if part not in {"", "."}
        )
        object_key = f"{clean_prefix}/{uuid4()}.{clean_suffix}".lstrip("/")
        target = self._resolve(object_key)

        def write() -> None:
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix(f"{target.suffix}.tmp")
            temporary.write_bytes(data)
            temporary.replace(target)

        await asyncio.to_thread(write)
        return object_key

    async def read_bytes(self, object_key: str) -> bytes:
        target = self._resolve(object_key)
        try:
            return await asyncio.to_thread(target.read_bytes)
        except FileNotFoundError as exc:
            raise AppError(
                "private_file_not_found", "Stored private file is unavailable.", 410
            ) from exc

    async def delete(self, object_key: str) -> None:
        target = self._resolve(object_key)

        def remove() -> None:
            target.unlink(missing_ok=True)
            parent = target.parent
            while parent != self.root:
                try:
                    parent.rmdir()
                except OSError:
                    break
                parent = parent.parent

        await asyncio.to_thread(remove)

    async def signed_read_url(self, object_key: str, expires_seconds: int = 300) -> str:
        del expires_seconds
        self._resolve(object_key)
        raise AppError(
            "signed_urls_unavailable",
            "Local private storage does not expose signed public URLs.",
            501,
        )
