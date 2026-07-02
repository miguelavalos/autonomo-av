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

- The private AVALSYS preflight must pass for `--app autonomo-av --intent
  testflight`, and `apps/ios/scripts/check-ios-release-preflight.sh --env prod
  --configuration Release` must pass before archive/export/upload.
- The release Mac must be signed into the Apple Developer team or use an App
  Store Connect API key when running archive/export with
  `--allow-provisioning-updates`.
- Real-device Share Extension smoke still needs a connected, trusted iPhone.
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
is coherent. Real iPhone/share-extension smoke needs a connected, trusted
device and a fixed/updated local Simulator runtime.

## Local Signing, Archive, and Export Update - 2026-07-02

Checks run from `apps/ios`:

- Xcode automatic provisioning created working dev profiles for
  `com.avalsys.autonomoav.dev` and `com.avalsys.autonomoav.dev.share`.
- Xcode automatic provisioning created working production archive profiles for
  `com.avalsys.autonomoav` and `com.avalsys.autonomoav.share`.
- `scripts/check-ios-signing-readiness.sh --env prod --mode testflight` now
  distinguishes App Store/TestFlight profiles from development profiles and
  passes after local export provisioning.
- `scripts/ios-release-archive.sh --allow-provisioning-updates` passed and
  produced a verified production `.xcarchive`.
- `scripts/ios-export-testflight-ipa.sh --archive <archive>
  --allow-provisioning-updates` passed and produced a verified local
  App Store Connect `.ipa` without uploading.

## First App Store Connect Upload - 2026-07-02

After the App Store Connect app record for `com.avalsys.autonomoav` was created,
the first upload attempt reached Apple and failed on App Store validation because
the app bundle did not include `CFBundleIconName` or a complete iPhone
`AppIcon.appiconset`.

The iOS target now includes a provisional RGB `AppIcon` set, declares
`CFBundleIconName=AppIcon`, and keeps `ASSETCATALOG_COMPILER_APPICON_NAME` in
`project.yml` for future project regeneration. A new archive was created and
uploaded successfully:

- archive: `.derived-data/release-archives/AutonomoAV-0.1.0-1-2026-07-02-111529.xcarchive`
- version: `0.1.0`
- build: `1`
- destination: App Store Connect upload
- result: Xcode reported `Upload succeeded`; the package entered Apple
  processing.

The next release step is to wait for Apple processing, resolve any processing
email from App Store Connect if it appears, and enable the build for internal
TestFlight testing. Future automation should use an App Store Connect API key
once that credential is available.
