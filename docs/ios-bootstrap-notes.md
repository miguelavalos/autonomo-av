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
