# Autonomo AV iOS

SwiftUI iPhone intake app for Autonomo AV.

The app uses Account AV for session restore and bearer tokens, uploads through
`/v1/apps/autonomo/*`, and drains Share Extension PDF/image handoffs from the
configured app group before retrying pending intake.

## iOS

```bash
xcodegen generate
xcodebuild -project AutonomoAV.xcodeproj -scheme AutonomoAV -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Use `scripts/generate-ios-local-xcconfig.sh --env dev` from this folder when
private local Account AV/API values are available. The generated
`Config/Local.xcconfig` file is ignored and must stay out of git.
