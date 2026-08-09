# Stride

iOS step-tracking app. SwiftUI. Built from the Phase 1 technical handoff.

## This folder was authored on Windows

Xcode cannot run here. The sources are complete and buildable; generate the Xcode
project on a Mac:

```bash
brew install xcodegen
xcodegen generate
open Stride.xcodeproj
```

`project.yml` defines both targets (app + widget extension), entitlements, and
Info.plist keys.

## Fonts

`Archivo` and `JetBrains Mono` are not bundled — download the TTFs from Google Fonts
and drop them in `Stride/Resources/Fonts/`. `project.yml` already lists that folder,
and `Info.plist` already declares the filenames under `UIAppFonts`.

Until they are present, `Type.swift` falls back to system fonts automatically
(`.rounded` is never used — the fallback is plain system + monospaced).

Required files:

```
Archivo-Regular.ttf      Archivo-Medium.ttf     Archivo-SemiBold.ttf
Archivo-Bold.ttf         Archivo-ExtraBold.ttf  Archivo-Black.ttf
JetBrainsMono-Regular.ttf  JetBrainsMono-Medium.ttf
```

## Layout

```
Stride/
  StrideApp.swift        entry point
  Design/                tokens, shared components, avatar
  Models/                data models + AppState
  Logic/                 streaks, points, nudges, step sources
  Copy/                  every string in the app, verbatim from the handoff
  Navigation/            Route enum + root switch
  Screens/               29 screens, one file each
StrideWidget/            WidgetKit extension
```

## Open items (handoff §9) — defaults applied

All four are resolved with a default and marked `// TODO(open):` in code.

| Item | Default applied | Where |
|---|---|---|
| App name | `Stride` | `project.yml`, `Copy.settingsFooter` |
| Points formula | 100/goal-day (automatic steps only), weekly bonus defined but unwired | `Logic/Points.swift` |
| Motion explainer screen | Built but skipped in the default flow | `Navigation/Route.swift` |
| Milestone copy beyond 7 | Table for 7/14/21/28/35/50/75/100 + fallback | `Copy/Copy.swift` |

## Not wired up

Firebase, Sign in with Apple, and Google Sign-In are stubbed behind
`Logic/AuthService.swift` protocol — no SDK dependency is declared, so the project
builds clean without a Firebase project existing yet. Auth screens call the stub and
advance.
