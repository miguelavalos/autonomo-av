# Autonomo AV iOS Bootstrap Notes

Date: 2026-07-01

This first iPhone scaffold lives in `public/autonomo-av/apps/ios` because no
existing public Autonomo app was present under `public/`.

Scope kept intentionally narrow:

- signed-in-only SwiftUI shell;
- Account AV wrapped behind an app-local account controller;
- import/scan/share capture surfaces for Autonomo intake;
- authenticated backend calls through `/v1/apps/autonomo/*`;
- prepared-upload support for both signed upload URLs and the authenticated
  API fallback;
- local pending upload metadata and retry state;
- app-group handoff from the Share Extension into the containing app's pending
  intake queue;
- backend-compatible upload payloads with `originalFilename`, `contentType`,
  `byteSize`, SHA-256 checksum, and V1-supported MIME filtering;
- no direct D1/R2/provider access;
- no private suite code changes.

The Share Extension target is present and labeled `Enviar a Autonomo AV Inbox`.
It now saves PDF/image share items into the configured app group
(`AUTONOMOAV_APP_GROUP_IDENTIFIER`) under `ShareInbox/Pending`. The containing
app drains that folder after Account AV session restore, imports files as
`ios_share`, and uploads them with the app's existing Account AV bearer token.

The containing app bootstraps the Autonomo workspace before remote refresh or
pending upload, then uses the backend prepared-upload contract. It rejects local
files outside the V1 backend allowlist: PDF, JPEG, PNG, WebP, HEIC, and HEIF.

Remaining live blockers:

- The Apple developer account/provisioning profile must include the dev and prod
  app groups (`group.com.avalsys.autonomoav.dev` and
  `group.com.avalsys.autonomoav`) for device/TestFlight builds.
- The private AVALSYS preflight must pass for `--app autonomo-av --intent
  testflight`, and `apps/ios/scripts/check-ios-release-preflight.sh --env prod
  --configuration Release` must pass before archive/export/upload.
- `apps/ios/scripts/check-ios-signing-readiness.sh --env prod --mode
  testflight` must pass on the release Mac before the first signed archive.
- The extension intentionally does not read or store Account AV tokens. If
  upload directly from the extension is required later, add an extension-safe
  backend handoff route rather than copying bearer tokens into the extension.

## Local Validation Update - 2026-07-01

Checks run from `apps/ios`:

- `scripts/check-ios-release-preflight.sh --env dev --configuration Debug --skip-build`:
  passed. The effective dev runtime config resolves to the preview Account AV
  API, preview Autonomo API, `com.avalsys.autonomoav.dev`,
  `group.com.avalsys.autonomoav.dev`, and a redacted `pk_test_` publishable key.
- XcodeBuildMCP `build_sim` with the configured `iPhone 17` simulator failed
  before build because this Mac cannot currently resolve that simulator. Xcode
  also reports CoreSimulator `1051.54.0` is older than the Xcode build's
  expected `1051.55.0`.
- Fallback generic simulator build passed:
  `xcodebuild -project AutonomoAV.xcodeproj -scheme AutonomoAV -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`.
- `scripts/check-ios-signing-readiness.sh --env dev --mode device-dev` remains
  blocked on this Mac: missing Apple Development identity for team
  `935PM55U6R` and missing local provisioning profiles for
  `com.avalsys.autonomoav.dev` and `com.avalsys.autonomoav.dev.share` with app
  group `group.com.avalsys.autonomoav.dev`.

Conclusion: the iOS project compiles without signing and the dev runtime config
is coherent. Real iPhone/share-extension smoke needs Apple signing identity,
matching app-group profiles, and a fixed/updated local Simulator runtime.
