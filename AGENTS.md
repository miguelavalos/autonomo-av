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
- Share Extensions must not read or store Account AV bearer tokens. They hand
  compatible files to the containing app through the configured App Group.
