# Autonomo AV

Public native and web client workspace for Autonomo AV.

Autonomo AV V1 is a signed-in business-document intake product:

```text
capture or upload -> backend intake queue -> AI draft -> manual review
```

The backend, Admin AV operator surface, and product documentation live in the
private AVALSYS suite. This public workspace contains the user-facing clients.

## Apps

- `apps/ios`
  Native SwiftUI iPhone intake app with Account AV sign-in boundary, scan/files
  import, local retry state, backend upload client, and Share Extension scaffold
  labeled `Enviar a Autonomo AV Inbox`.
- `apps/web`
  Minimal signed-in web app with inbox-first workflow, drag/drop upload,
  review, quarter view, settings, fixture mode, and live backend client wiring.

## Docs

- `AGENTS.md`
- `docs/ios-bootstrap-notes.md`
- `docs/web-bootstrap-notes.md`

## Local Checks

```bash
cd apps/web
bun install
bun run typecheck
bun run build
```

```bash
cd apps/ios
xcodegen generate
scripts/check-ios-release-preflight.sh --env dev --configuration Debug
xcodebuild -project AutonomoAV.xcodeproj -scheme AutonomoAV -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Private API URLs, Clerk keys, and Apple team values must stay in ignored local
config files.

## Web Runtime Modes

`apps/web` starts in fixture mode by default with
`VITE_AUTONOMOAV_USE_FIXTURES=true`. Live mode uses Account AV auth when
`VITE_ACCOUNTAV_API_BASE_URL`, `VITE_ACCOUNTAV_PUBLISHABLE_KEY`, and
`VITE_AUTONOMOAV_API_BASE_URL` are set alongside
`VITE_AUTONOMOAV_USE_FIXTURES=false`. `VITE_AUTONOMOAV_DEV_BEARER_TOKEN`
remains only as a temporary local fallback when Account AV auth config is not
available.

## CI

GitHub Actions run:

- web typecheck and production build;
- iOS XcodeGen, dev runtime config check, and generic simulator build without
  signing.

iOS unit tests are intentionally not part of the first CI gate until the
simulator/runtime lane is stable for this new product repo.
