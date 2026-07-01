# Autonomo AV Web Bootstrap Notes

Status: minimal signed-in user web V1 scaffold notes.

The web app lives at `apps/web` and is scoped to the signed-in Autonomo AV user
surface: inbox, upload, review, quarter, and settings.

## Runtime Modes

Fixture mode is on by default and does not require Account AV auth:

```text
VITE_AUTONOMOAV_USE_FIXTURES=true
```

Fixture mode keeps the app usable before local Account AV auth and Autonomo
backend runtime are available. The fixture adapter exercises queued, drafted,
needs-review, reviewed, failed, upload-created, counterparty-created, reviewed
save, reprocess, duplicate, ignored, quarter summary, and optional email alias
states.

Live backend mode with Account AV auth:

```text
VITE_AUTONOMOAV_USE_FIXTURES=false
VITE_AUTONOMOAV_API_BASE_URL=https://api-account-av-preview.avalsys.com
VITE_ACCOUNTAV_API_BASE_URL=https://api-account-av-preview.avalsys.com
VITE_ACCOUNTAV_PUBLISHABLE_KEY=<Clerk publishable key for the matching Account AV environment>
```

When Account AV env vars are present, the web app wraps the inbox in
`AccountAvProvider`, shows a `/sign-in` boundary, and the Autonomo API client
retrieves the current session token through `useAccountToken()`.

Temporary local live fallback:

```text
VITE_AUTONOMOAV_USE_FIXTURES=false
VITE_AUTONOMOAV_API_BASE_URL=https://api-account-av-preview.avalsys.com
VITE_AUTONOMOAV_DEV_BEARER_TOKEN=<short-lived local bearer token>
```

The dev bearer token is only an adapter fallback when Account AV auth config is
not available. Product UI reads auth state from the local `AutonomoAuthProvider`
and does not access the token env var directly.

The API client uses the Autonomo backend paths from the V1 contract:

- `POST /v1/apps/autonomo/workspace/bootstrap`
- `POST /v1/apps/autonomo/uploads/prepare`
- `PUT /v1/apps/autonomo/uploads/:uploadId`
- `POST /v1/apps/autonomo/uploads/:uploadId/complete`
- `GET /v1/apps/autonomo/documents`
- `GET /v1/apps/autonomo/documents/:documentId`
- `GET /v1/apps/autonomo/documents/:documentId/file`
- `PATCH /v1/apps/autonomo/documents/:documentId`
- `GET /v1/apps/autonomo/counterparties`
- `POST /v1/apps/autonomo/counterparties`
- `GET /v1/apps/autonomo/quarter-summary?quarter=YYYY-Qn`

## Live Preview Smoke Path

1. Configure the matching preview env values for Account AV and Autonomo AV:
   `VITE_AUTONOMOAV_USE_FIXTURES=false`,
   `VITE_AUTONOMOAV_API_BASE_URL`, `VITE_ACCOUNTAV_API_BASE_URL`, and
   `VITE_ACCOUNTAV_PUBLISHABLE_KEY`.
2. Run `cd apps/web && bun install && bun run dev`.
3. Open `http://localhost:5195/sign-in`, sign in with Account AV, then continue
   to `/`.
4. Confirm the header shows `Live` and `Account AV`.
5. Verify workspace bootstrap loads, the inbox lists documents, and a small
   supported PDF/image upload reaches queued state.
6. Open a document, preview/download the file, save a reviewed/ignored/duplicate
   action, and confirm quarter summary refreshes.
7. Check the browser console and network panel for auth, CORS, or token
   retrieval errors. Do not copy tokens into logs or screenshots.

## Cloudflare Web Deploy

`apps/web` deploys as static Worker Assets, with SPA fallback enabled for the
signed-in app routes and the public legal routes:

- preview: `https://autonomo-av-preview.avalsys.com`
- production: `https://autonomo-av.avalsys.com`

Use these commands from `apps/web`:

```bash
bun run build:preview
bun run build:preview:live
bun run deploy:preview:dry-run
bun run deploy:preview

bun run build:production
bun run build:production:live
bun run deploy:production:dry-run
bun run deploy:production
```

The Cloudflare build scripts force `VITE_AUTONOMOAV_USE_FIXTURES=false`, clear
`VITE_AUTONOMOAV_DEV_BEARER_TOKEN`, and keep email intake disabled so public
deploys cannot accidentally ship fixture mode, a local bearer token, or a
placeholder email alias. If `VITE_ACCOUNTAV_PUBLISHABLE_KEY` is not available,
the deployed shell still serves `/privacy`, `/terms`, `/delete-account`, and
`/support`, while signed-in routes show the live-auth missing state.

The `build:*:live` and `deploy:*` scripts resolve Account AV's publishable key
from the private suite with Varlock/Infisical. Production live builds fail fast
unless the key has the `pk_live_` prefix.

The preview and production Wrangler configs use a tiny Worker entrypoint
(`src/worker.ts`) with an explicit `ASSETS` binding. The Worker delegates every
request to `env.ASSETS.fetch(request)`. Keep that binding in place: without it,
Cloudflare can serve the SPA HTML fallback for hashed JS asset paths, which
causes a blank page because the browser receives HTML instead of JavaScript.

Quick deployed preview check:

```bash
curl -sS -D - https://autonomo-av-preview.avalsys.com/ -o /tmp/autonomo-preview.html
curl -sS -D - https://autonomo-av-preview.avalsys.com/assets/<bundle>.js -o /tmp/autonomo-preview.js
rg -n "AsyncLocalStorage|tanstack-react-start|start-storage-context" /tmp/autonomo-preview.js || true
```

The JS response must be `content-type: text/javascript`, and the client bundle
must not include the server-only TanStack Start auth code.

## Follow-Up Boundary

The app currently keeps contract-shaped TypeScript types locally because
`@avapps/contracts` is private to `private/avalsys-suite`. When Autonomo web has
a published/shared contract package available to public product apps, replace
the local type mirrors with shared schemas and runtime parsing.

The shared Account AV web package does not yet expose `autonomoav` in its public
`AccountAvAppId` union, so the Autonomo adapter casts the app id locally while
still sending `autonomoav` to Account AV. Remove that cast when the shared
package adds the app id.
