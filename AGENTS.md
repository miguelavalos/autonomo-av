# Agent Notes

Autonomo AV is part of the private AVALSYS workspace. Before touching signed
native runtime, Account AV auth, preview/prod endpoints, App Groups, TestFlight,
App Store Connect, or release work, run the private suite preflight from
`private/avalsys-suite`:

```bash
bash scripts/agent-preflight.sh --app autonomo-av --intent <intent>
```

Use the most specific intent:

- `code` for normal implementation;
- `signed-runtime` for native/web validation against Account AV and backend
  state;
- `testflight` for archive, export, upload, or App Store Connect build work;
- `release` for App Review or public launch work.

Read every doc printed by the preflight before executing commands. If the
preflight fails, fix the missing guard or stop and report the blocker.

## Public Repo Rules

- Keep private Account AV keys, backend URLs, Apple team overrides, provisioning
  profiles, and generated `apps/ios/Config/Local.xcconfig` or
  `apps/macos/Config/Local.xcconfig` out of git.
- Do not archive, export, or upload TestFlight builds from ad-hoc commands.
  Follow the private Autonomo AV App Store publish runbook.
- For iOS runtime checks, use the scripts under `apps/ios/scripts/`.
- For macOS runtime checks, use the scripts under `apps/macos/scripts/`; for
  CI-equivalent local validation, use `scripts/macos-ci-test.sh`.
- The Share Extension label is `Enviar a Autonomo AV Inbox`.
- The macOS Share Extension label is `Autonomo AV Inbox`.
- Share Extensions must not read or store Account AV bearer tokens. They may
  read only the tokenless Autonomo AV access snapshot in the App Group; without
  a fresh signed-in Pro snapshot they must reject the handoff before copying
  files. The containing app drains compatible files from the App Group only
  after Account AV login and Pro access are active.

## Verification

- Before opening a pull request, run `scripts/macos-ci-test.sh` once from the
  repository root. It regenerates the macOS project, runs the dev runtime and
  share extension preflight and runs the macOS unit tests, the same as the
  `macOS CI` workflow.
- The full suite, release builds and device runs belong to CI and to the
  required checks; do not repeat them locally unless the change needs it.

## Review

- The independent review that sets the `agent-review` status follows
  [`project-bootstrap/docs/REVIEW.md`](https://github.com/miguelavalos/project-bootstrap/blob/main/docs/REVIEW.md),
  found at `~/github/project-bootstrap/docs/REVIEW.md` on agent machines.
- The reviewer is a fresh agent that did not write the change.
- The review comment starts with `PASS` or `BLOCK`.
