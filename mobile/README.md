# Personal Health OS mobile

The Flutter client targets iPhone/iOS first and retains Android as a secondary
compatibility target. The committed `ios/` directory is the canonical mobile
runner; do not regenerate it during routine development.

Current distribution is **Private Personal Sideload**: cloud macOS produces
unsigned IPAs; the owner re-signs with a free Apple Account using Windows
Sideloadly / AltStore Classic. See `PERSONAL_SIDELOAD_WINDOWS.md`,
`FREE_SIGNING_ENTITLEMENT_AUDIT.md`, and `IPHONE_PERSONAL_ACCEPTANCE.md` at the
repository root. No locally owned Mac or paid Apple membership is required.
Refresh the personal signature about every seven days. Future paid signing
remains documented in `CLOUD_IOS_RELEASE.md` but is suspended. Local Xcode
instructions in `IOS_BUILD_SETUP.md` are optional debugging only.
