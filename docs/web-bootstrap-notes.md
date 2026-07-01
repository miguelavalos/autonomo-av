# Autonomo AV Web Bootstrap Notes

Status: minimal signed-in user web V1 scaffold notes.

The web app lives at `apps/web` and is scoped to the signed-in Autonomo AV user
surface: inbox, upload, review, quarter, and settings.

## Runtime Modes

Fixture mode is on by default:

```text
VITE_AUTONOMOAV_USE_FIXTURES=true
```

Fixture mode keeps the app usable before local Account AV auth and Autonomo
backend runtime are available. The fixture adapter exercises queued, drafted,
needs-review, reviewed, failed, upload-created, counterparty-created, reviewed
save, reprocess, duplicate, ignored, quarter summary, and optional email alias
states.

Live backend mode:

```text
VITE_AUTONOMOAV_USE_FIXTURES=false
VITE_AUTONOMOAV_API_BASE_URL=https://api-account-av-preview.avalsys.com
VITE_AUTONOMOAV_DEV_BEARER_TOKEN=<Account AV bearer token until Account AV web is wired>
```

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

## Follow-Up Boundary

The app currently keeps contract-shaped TypeScript types locally because
`@avapps/contracts` is private to `private/avalsys-suite`. When Autonomo web has
a published/shared contract package available to public product apps, replace
the local type mirrors with shared schemas and runtime parsing.
