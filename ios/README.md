# Morgenlinie for iOS

SwiftUI, iOS 26+, Swift 6, SwiftData, SwiftUI `WebView`/`WebPage`. No dependencies.

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd ios && xcodegen generate && open Morgenlinie.xcodeproj
```

Before installing on a phone: set your team under Signing & Capabilities and pick the final bundle ID (placeholder `com.lskupincardosa.morgenlinie`; if it changes, also change the `BGTaskSchedulerPermittedIdentifiers` entry and `AppConfig.refreshTaskID`). Free Apple ID builds expire after 7 days.

## Layout

- `App/AppConfig.swift`: base URL, refresh time, task ID (the only place with URLs)
- `Sync/EditionSync.swift`: `editions.json` with ETag, sha256-verified downloads, never deletes local editions
- `Sync/BackgroundRefresh.swift`: `BGAppRefreshTask` for the next 07:55 Europe/Berlin
- `Views/ReaderScreen.swift`, `Views/EditionWebView.swift`: reader; anchors stay in place, http(s) links open in Safari View
- `Views/ReadingLayout.swift`: list and reader side by side on wide screens (iPad, unfolded iPhone Duo), split at the fold when iOS 27.1+ reports one; iPhones keep the single column
- Editions live in Application Support/Editions/YYYY-MM-DD.html

## Testing against a local copy

Debug builds read `MORGENLINIE_BASE_URL`:

```sh
python3 -m http.server 8765 --bind 127.0.0.1   # in the repo root
SIMCTL_CHILD_MORGENLINIE_BASE_URL=http://localhost:8765/ xcrun simctl launch booted com.lskupincardosa.morgenlinie
```

In Xcode, set it under Scheme › Run › Arguments › Environment Variables.

Background refresh can be triggered from the debugger:
`e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.lskupincardosa.morgenlinie.refresh"]`
