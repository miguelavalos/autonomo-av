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
xcodebuild -project AutonomoAV.xcodeproj -scheme AutonomoAV -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Private API URLs, Clerk keys, and Apple team values must stay in ignored local
config files.
