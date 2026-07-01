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
bun run build:production
```

```bash
cd apps/ios
xcodegen generate
scripts/check-ios-release-preflight.sh --env dev --configuration Debug
scripts/check-ios-signing-readiness.sh --env dev --mode device-dev
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

Cloudflare deployment builds use `bun run build:preview` and
`bun run build:production`. Those builds force
`VITE_AUTONOMOAV_USE_FIXTURES=false`, set the matching public legal URLs, and
clear `VITE_AUTONOMOAV_DEV_BEARER_TOKEN` before bundling. Email intake is
disabled in this first public web deploy. If
`VITE_ACCOUNTAV_PUBLISHABLE_KEY` is absent, signed-in routes show the live-auth
missing state while `/privacy`, `/terms`, `/delete-account`, and `/support`
remain public.

Deploy commands use `build:preview:live` and `build:production:live`, which
resolve `VITE_ACCOUNTAV_PUBLISHABLE_KEY` from the private suite through
Varlock/Infisical before bundling. Production live builds require a `pk_live_`
publishable key.

## Web Deploy

```bash
cd apps/web
bun run deploy:preview:dry-run
bun run deploy:preview
bun run deploy:production:dry-run
bun run deploy:production
```

The deploy scripts use the private suite's `wrangler-account.sh` wrapper from
the shared workspace, so Cloudflare account selection and API tokens stay out of
this public repo.

## CI

GitHub Actions run:

- web typecheck and deploy-safe production build;
- iOS XcodeGen, dev runtime config check, and generic simulator
  `build-for-testing` without signing.

iOS unit tests are intentionally not part of the first CI gate until the
simulator/runtime lane is stable for this new product repo. The iOS CI still
compiles the test bundle through `build-for-testing`.
