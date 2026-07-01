# Autonomo AV iOS

SwiftUI iPhone intake app for Autonomo AV.

The app uses Account AV for session restore and bearer tokens, uploads through
`/v1/apps/autonomo/*`, and drains Share Extension PDF/image handoffs from the
configured app group before retrying pending intake.

The live upload client bootstraps the user's Autonomo workspace, sends the
backend V1 prepare payload (`originalFilename`, `contentType`, `byteSize`,
`sha256`, `source`), uploads with the prepared URL or API fallback, and then
completes the upload so the backend creates the intake queue item.

## iOS

```bash
xcodegen generate
xcodebuild -project AutonomoAV.xcodeproj -scheme AutonomoAV -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Use `scripts/generate-ios-local-xcconfig.sh --env dev` from this folder when
private local Account AV/API values are available. The generated
`Config/Local.xcconfig` file is ignored and must stay out of git.

Before any signed device, TestFlight, or App Store work, run the private
AVALSYS preflight from `private/avalsys-suite` and then run the local iOS
guardrail:

```bash
scripts/check-ios-release-preflight.sh --env dev --configuration Debug
```

For production/TestFlight, generate ignored production config first, then run:

```bash
scripts/generate-ios-local-xcconfig.sh --env prod
scripts/check-ios-release-preflight.sh --env prod --configuration Release
scripts/check-ios-signing-readiness.sh --env prod --mode testflight
scripts/ios-release-archive.sh
```

The release preflight does not archive, export, upload, or contact App Store
Connect. It validates resolved runtime config plus the App Group/Share Extension
shape required for `Enviar a Autonomo AV Inbox`.

The signing readiness check also does not archive, export, upload, or contact
App Store Connect. It only verifies that this Mac has the expected Apple signing
identity and local provisioning profiles for the app and Share Extension.

The release archive script creates and verifies a signed `.xcarchive`, but it
intentionally does not export, upload, or contact App Store Connect. Add
`--allow-provisioning-updates` only when the release Mac is signed into the
correct Apple Developer team and Xcode should repair local profiles.
