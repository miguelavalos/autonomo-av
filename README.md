# Autonomo AV

Public native and web client workspace for Autonomo AV.

Autonomo AV V1 is a signed-in business-document register plus Pro AI intake
product:

```text
manual record -> reviewed quarter register
web/iOS/macOS capture -> Pro AI queue -> AI draft -> manual review
```

The backend, Admin AV operator surface, and product documentation live in the
private AVALSYS suite. This public workspace contains the user-facing clients.

## Apps

- `apps/ios`
  Native SwiftUI iPhone intake app with Account AV sign-in boundary, scan/files
  import, local retry state, backend upload client, Pro access gate, and Share
  Extension scaffold labeled `Enviar a Autonomo AV Inbox`.
- `apps/macos`
  Native SwiftUI macOS intake app scaffold with MenuBarExtra, main inbox window,
  local retry queue reuse, Finder/Open With, Services, Share Extension,
  drag/drop and file picker import, and Account AV upload wiring through the
  shared Apple upload core. Import surfaces require Account AV login plus
  Autonomo AV Pro before staging files. The Share Extension writes only to the
  app group inbox after finding a fresh tokenless Pro access snapshot; the
  containing app drains and uploads only while Pro access is active.
- `apps/web`
  Minimal signed-in web app with minimum business onboarding, manual records
  register, filters, create/edit review workflow, quarter view, settings,
  fixture mode, live backend client wiring, and a Pro AI intake surface that
  shares the backend queue with iOS and macOS.

## Docs

- `AGENTS.md`
- `docs/ios-bootstrap-notes.md`
- `docs/web-bootstrap-notes.md`

## Local Checks

```bash
cd apps/web
pnpm install
vp run typecheck
vp run build
vp run build:production
```

```bash
cd apps/ios
xcodegen generate
scripts/check-ios-release-preflight.sh --env dev --configuration Debug --skip-build
scripts/check-ios-signing-readiness.sh --env dev --mode device-dev
xcodebuild -project AutonomoAV.xcodeproj -scheme AutonomoAV -destination 'generic/platform=iOS Simulator' -derivedDataPath .DerivedData-autonomoav-ios-build build-for-testing CODE_SIGNING_ALLOWED=NO
du -sh .DerivedData-autonomoav-ios-build
rm -rf .DerivedData-autonomoav-ios-build
```

```bash
cd apps/macos
xcodegen generate
scripts/check-macos-runtime-config.sh --env dev --configuration Debug
scripts/check-macos-release-preflight.sh --env dev --configuration Debug --skip-build
scripts/check-macos-signing-readiness.sh --env dev --mode device-dev
xcodebuild test -project AutonomoAVMac.xcodeproj -scheme AutonomoAVMac -destination 'platform=macOS' -derivedDataPath .DerivedData-autonomoav-macos-test CODE_SIGNING_ALLOWED=NO
du -sh .DerivedData-autonomoav-macos-test
rm -rf .DerivedData-autonomoav-macos-test
```

For a local signed macOS QA build, inspect the built `.app` before smoking
Finder/Open With or the menu bar app:

```bash
scripts/check-macos-signed-build.sh --env dev --app /path/to/Autonomo\ AV.app
```

The macOS project registers App Groups for the containing app and share
extension through the generated Xcode project. On a development machine with
Apple account access, a signed build with `-allowProvisioningUpdates` should
create or refresh app-specific profiles for both bundle identifiers. Treat the
Share Extension/App Group handoff as proven only when
`check-macos-signing-readiness.sh` passes and
`check-macos-signed-build.sh` reports app-specific embedded profiles with
`app-group-proof=yes`. A `local-qa-ready` build with wildcard embedded profiles
is still useful for local Finder/Open With and menu bar smokes, but not for
claiming the share handoff is fully provisioned.

For local signed locked-access smokes, use the aggregate script. The Share
Extension registration smoke validates the signed `.appex` through PlugInKit;
the Share Extension discovery smoke stages the app under a temporary
`~/Applications` folder and verifies that macOS lists `Autonomo AV Inbox` for a
synthetic PDF. The Finder/Open With and Services scripts launch the signed app
with an isolated local queue, require locked access by default, invoke the macOS
intake surface with a synthetic PDF, and verify that no file is staged before
login plus Pro access:

```bash
scripts/smoke-macos-signed-local.sh --env dev --app /path/to/Autonomo\ AV.app
```

The aggregate script runs these individual checks:

```bash
scripts/smoke-macos-share-extension-registration.sh --env dev --app /path/to/Autonomo\ AV.app
scripts/smoke-macos-share-extension-discovery.sh --env dev --app /path/to/Autonomo\ AV.app
scripts/smoke-macos-open-with.sh --env dev --app /path/to/Autonomo\ AV.app
scripts/smoke-macos-services.sh --env dev --app /path/to/Autonomo\ AV.app
```

For the CI-equivalent macOS lane from the repo root:

```bash
scripts/macos-ci-test.sh
```

For local desktop smoke runs against a signed sandboxed build, launch the app
through LaunchServices with `AUTONOMOAV_LOCAL_INTAKE_ROOT_URL` pointed at a
temporary folder inside the app container, for example under
`~/Library/Containers/com.avalsys.autonomoav.mac.dev/Data/tmp`. This keeps
Open With/Finder import validation out of the user's real Application Support
queue while preserving the same app code path.

Private API URLs, Clerk keys, Apple team values, and Sentry DSNs must stay in
ignored local config files. Generate the macOS local config with
`apps/macos/scripts/generate-macos-local-xcconfig.sh --env dev|prod`; the output
is `apps/macos/Config/Local.xcconfig` and must remain ignored.

## Web Runtime Modes

`apps/web` starts in fixture mode by default with
`VITE_AUTONOMOAV_USE_FIXTURES=true`. Live mode uses Account AV auth when
`VITE_ACCOUNTAV_API_BASE_URL`, `VITE_ACCOUNTAV_PUBLISHABLE_KEY`, and
`VITE_AUTONOMOAV_API_BASE_URL` are set alongside
`VITE_AUTONOMOAV_USE_FIXTURES=false`. `VITE_AUTONOMOAV_DEV_BEARER_TOKEN`
remains only as a temporary local fallback when Account AV auth config is not
available.

Cloudflare deployment builds use `vp run build:preview` and
`vp run build:production`. Those builds force
`VITE_AUTONOMOAV_USE_FIXTURES=false`, set the matching public legal URLs, and
clear `VITE_AUTONOMOAV_DEV_BEARER_TOKEN` before bundling. Email intake is
disabled in this first public web deploy. If
`VITE_ACCOUNTAV_PUBLISHABLE_KEY` is absent, signed-in routes show the live-auth
missing state while `/privacy`, `/terms`, `/delete-account`, and `/support`
remain public.

The Cloudflare deploy uses a Worker Assets binding through `apps/web/src/worker.ts`
so hashed JS/CSS assets are served by the assets runtime and SPA fallback stays
limited to app routes.

Deploy commands use `build:preview:live` and `build:production:live`, which
resolve `VITE_ACCOUNTAV_PUBLISHABLE_KEY` from the private suite through
Varlock/Infisical before bundling. Production live builds require a `pk_live_`
publishable key.

## Web Deploy

```bash
cd apps/web
vp run deploy:preview:dry-run
vp run deploy:preview
vp run deploy:production:dry-run
vp run deploy:production
```

The deploy scripts use the private suite's `wrangler-account.sh` wrapper from
the shared workspace, so Cloudflare account selection and API tokens stay out of
this public repo.

## CI

GitHub Actions run:

- web typecheck and deploy-safe production build;
- iOS XcodeGen, dev runtime config check, and generic simulator
  `build-for-testing` without signing.
- macOS XcodeGen, dev runtime/share-extension/security preflight, and unsigned
  unit tests with an uploaded `.xcresult` on failure.

iOS unit tests are intentionally not part of the first CI gate until the
simulator/runtime lane is stable for this new product repo. The iOS CI still
compiles the test bundle through `build-for-testing`.
