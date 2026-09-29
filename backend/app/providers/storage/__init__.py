from app.core.config import get_settings
from app.providers.storage.local import LocalStorageProvider


def get_storage_provider() -> LocalStorageProvider:
    return LocalStorageProvider(get_settings().upload_dir)


__all__ = ["LocalStorageProvider", "get_storage_provider"]
