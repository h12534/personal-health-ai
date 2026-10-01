from app.core.config import Settings
from app.providers.push.base import PushMessage, PushResult


class ApplePushProvider:
    """APNs boundary. Credentials are deliberately injected via Settings.

    The actual network transport stays disabled until the owner supplies Apple credentials;
    application services therefore remain testable and never depend on an APNs SDK.
    """

    name = "apple"

    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    async def send(self, message: PushMessage) -> PushResult:
        if not all(
            (
                self.settings.apns_team_id,
                self.settings.apns_key_id,
                self.settings.apns_auth_key_path,
                self.settings.apns_bundle_id,
            )
        ):
            return PushResult(accepted=False, error="apns_credentials_not_configured")
        return PushResult(accepted=False, error="apns_transport_requires_release_configuration")
