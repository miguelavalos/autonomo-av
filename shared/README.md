# Shared Code

This directory is the root for code shared across Autonomo AV clients.

## Layout

- `apple/`: Swift and Foundation code shared by Apple targets, such as iOS and macOS.
- `contracts/`: Platform-neutral contracts, fixtures, schemas, or generated inputs when backend and clients need one source of truth.

## Boundary

Keep SwiftUI views, app state, StoreKit or RevenueCat UI, and platform-specific orchestration inside each app target. Use `shared/apple` for Autonomo AV behavior that both iOS and macOS need to call in the same way.

Promote code here when at least two Apple clients need it, or when deleting the shared code would make the same behavior reappear in both clients.

## Validation

When changing `shared/apple`:

1. Regenerate the iOS project from `apps/ios/project.yml`.
2. Run the focused iOS unit tests.
3. Validate macOS once the macOS target exists.
