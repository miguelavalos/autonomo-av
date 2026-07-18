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

The shared `AutonomoAV` scheme includes 40 unit tests and three deterministic
guest-journey UI tests. The UI target validates signed-out onboarding, provider
choices, subscription disclosure and gating, redemption, and legal-link pair
consistency without starting authentication or purchase. Use a dedicated
iPhone simulator when running it locally so concurrent agents do not share
CoreSimulator state.

Use `scripts/generate-ios-local-xcconfig.sh --env dev` from this folder when
private local Account AV/API values are available. The generated
`Config/Local.xcconfig` file is ignored and must stay out of git. When present,
the generated config includes `AUTONOMOAV_IOS_SENTRY_DSN`; never print or commit
the DSN value.

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
scripts/check-ios-signing-readiness.sh --env prod --mode device-dev
scripts/ios-release-archive.sh --allow-provisioning-updates
scripts/ios-export-testflight-ipa.sh --archive <path-from-archive> --allow-provisioning-updates
```

The release preflight does not archive, export, upload, or contact App Store
Connect. It validates resolved runtime config plus the App Group/Share Extension
shape required for `Enviar a Autonomo AV Inbox`.

The signing readiness check also does not archive, export, upload, or contact
App Store Connect. It only verifies that this Mac has the expected Apple signing
identity and local provisioning profiles for the app and Share Extension.

The release archive script creates a signed `.xcarchive`, repairs
`Sentry.framework.dSYM` when Sentry is embedded, and verifies the archive. It
intentionally does not export, upload, or contact App Store Connect. Add
`--allow-provisioning-updates` only when the release Mac is signed into the
correct Apple Developer team and Xcode should repair local profiles.

The TestFlight export script verifies the archive, exports a local App Store
Connect `.ipa`, and validates the exported app/Share Extension bundle IDs,
App Group entitlements, team id, and distribution profiles. It does not upload
by default; pass `--upload` explicitly only when you want xcodebuild to upload
to App Store Connect.
