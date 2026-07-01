# Autonomo AV iOS Bootstrap Notes

Date: 2026-07-01

This first iPhone scaffold lives in `public/autonomo-av/apps/ios` because no
existing public Autonomo app was present under `public/`.

Scope kept intentionally narrow:

- signed-in-only SwiftUI shell;
- Account AV wrapped behind an app-local account controller;
- import/scan/share capture surfaces for Autonomo intake;
- authenticated backend calls through `/v1/apps/autonomo/*`;
- local pending upload metadata and retry state;
- no direct D1/R2/provider access;
- no private suite code changes.

The Share Extension target is present and labeled `Enviar a Autonomo AV Inbox`.
It currently captures supported share items into a confirmation surface. Upload
from the extension itself still needs an approved app group/token bridge or a
backend handoff route, so the containing app remains the first working upload
path.
