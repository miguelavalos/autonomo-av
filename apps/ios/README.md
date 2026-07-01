# Autonomo AV iOS

SwiftUI iPhone intake app for Autonomo AV.

## iOS

```bash
xcodegen generate
xcodebuild -project AutonomoAV.xcodeproj -scheme AutonomoAV -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Use `scripts/generate-ios-local-xcconfig.sh --env dev` from this folder when
private local Account AV/API values are available. The generated
`Config/Local.xcconfig` file is ignored and must stay out of git.
