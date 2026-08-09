# Stride — Current State (compact handoff)

Read this first. It exists so a new Claude Code session doesn't need to
re-read the whole repo or re-derive history to get oriented. Written after
Phase 1.0.5 (foundation hardening) + the manual-entry removal, both merged
to `main` and verified via a real CI build + test run before merge.

## 1. Product principle

**"You move. It moves."**

The Figure is the product. Everything else (streak, points, leaderboard)
exists to give the Figure something to react to.

## 2. Product direction

- **Automatic movement only.** No manual step entry exists anywhere in the
  app or the data model's write path. This was a deliberate removal, not an
  oversight — see `CreditedSteps.swift`.
- **Premium / professional, not childish gamification.** Cold, factual,
  understated copy voice (`Copy.swift`). No exclamation marks, no mascot
  energy, no confetti.
- **The Figure is the primary differentiator.** Product investment should
  bias toward making the Figure feel alive and trustworthy over adding new
  screens or mechanics.
- **Health/activity data stays factual and trustworthy.** Nothing is ever
  inflated, estimated, or gamed. Automatic sensor data is the sole
  authority for anything competitive or reward-bearing.

## 3. Current architecture

- **`AppState`** (`Stride/Models/AppState.swift`) — single `ObservableObject`
  source of truth for the whole app. Owns `StepProvider`, persists to
  `UserDefaults` as one JSON snapshot.
- **`StepProvider`** (`Stride/Logic/StepProvider.swift`) — CMPedometer
  (primary) + HealthKit (optional, currently non-functional — no capability
  enabled on the App ID yet). Owns a `MovementClassifier`, three timers
  (classifier tick, hourly refresh, midnight rebase), and a foreground
  observer.
- **`MovementClassifier`** (`Stride/Logic/MovementClassifier.swift`) — pure,
  CoreMotion-free struct. Fed `(timestamp, cumulative steps)` samples,
  returns activity state / intensity / trend / session info. Unit-tested.
- **`MotionConfig`** (`Shared/Design/MotionConfig.swift`) — every tunable
  threshold and animation constant in one place (classification thresholds,
  session hysteresis, spring parameters, debounce intervals).
- **`StreakEngine`** (`Stride/Logic/StreakEngine.swift`) — pure streak
  math: `rollOver`, `reconcile` (catch-up on relaunch), `displayedStreak`
  (same-day live projection, never mutates persisted state), `Milestones`.
- **`Points`** (`Stride/Logic/Points.swift`) — flat 100/goal-day formula.
  Weekly bonus exists but is deliberately unwired (see §6).
- **`Router`** (`Stride/Navigation/Route.swift`, `RootView.swift`) — enum
  `Route` + `NavigationStack` path. `.home`/`.leaderboard`/`.profile` are
  tab roots (not pushed); `.milestone` is not a Route case at all — the
  Milestone screen is shown via `AppState.pendingMilestone` +
  `.fullScreenCover`.
- **`AvatarView` / `FigureShape`** (`Shared/Design/AvatarView.swift`) —
  the Figure. Raw `Path` line-art from hardcoded coordinates, 4 fixed
  poses. `LiveAvatar` is the reactive Home-screen version.
- **Persistence** — one JSON blob in `UserDefaults.standard`
  (`AppState.persist()`/`load()`). Writes are throttled via `Throttler`
  (`Stride/Logic/Throttler.swift`) — 5s coalescing for high-frequency step
  deltas, immediate/uncoalesced for rewards, purchases, and lifecycle
  events (background, sign-out, erase). No SwiftData/Core Data.

## 4. Current verified movement signals (`StepProvider`, published)

All exist and are unit-tested at the `MovementClassifier` level. **None are
consumed by any view yet** — they're the foundation for Phase 1.1, not
wired to UI.

- `activityState` (idle/walking/active) + `motionIntensity` (0...1) — the
  two that already drive `LiveAvatar` today.
- `movementTrend` (rising/steady/falling)
- `isInMovementSession`
- `movementSessionStartedAt`
- `movementSessionDuration`
- `lastMeaningfulMovementAt`
- `inactiveDuration` (optional — nil until first movement)
- `activeSecondsToday`

## 5. Current Figure capabilities

- **4 poses**, each with one fixed meaning: `standing` (home/profile/
  reveal), `raised` (milestone only), `slumped` (Day-1 comparison only),
  `running` (intro + LiveAvatar active state).
- **3 live states** on Home (`LiveAvatar`): idle (dimmed, still) / walking
  (standing + intensity-scaled bob/lean) / active (running + speed lines).
- **Goal breakthrough**: one coordinated reaction on crossing the daily
  goal — avatar forward-step-and-scale pulse, a brief ink flash on the
  progress bar, spring-settle on the counter, one haptic tap. Fires exactly
  once per qualifying day (edge-triggered in `AppState.applyLiveSteps`).
- **6 unlock transforms** (cosmetic overlays, purchasable with points):
  heavierLine, longShadow, steelOutline, motionTrail, inverted, and the
  earned-not-bought thirtyDayMark.
- **Reduce Motion**: `LiveAvatar` reads `@Environment(\.accessibilityReduceMotion)`.
  When on: no repeatForever bob, no spring overshoat, no breakthrough
  translation/scale — pose still changes, breakthrough becomes a brief
  restrained opacity dip instead.

## 6. Known deferred features (not started — explicitly out of scope until told otherwise)

- Premium Figure Engine / a continuous multi-state animation system beyond
  the current idle/walking/active
- Momentum (user-facing)
- Motion Echo
- Motion Moments / Moves (micro-missions)
- Record screen redesign
- Others/social (Leaderboard) redesign — currently mock/local-only friends
- Profile / Progression redesign
- HealthKit capability (code exists in `StepProvider`, entitlement not
  enabled on the App ID)
- Apple Watch support
- App Groups / widget real data (widget code exists, shows placeholder
  zeros without the entitlement)
- Notification scheduling (`NudgeEngine` exists, is never called —
  Settings has 3 distinct toggles now but nothing fires from them)
- Production auth (Firebase/Sign in with Apple/Google — currently a local
  stub, `LocalAuthService`, accepts any well-formed input)

## 7. Verification status (as of this handoff)

- Real `xcodegen generate` → `xcodebuild build` (iOS Simulator, Xcode
  26.6): **PASS**
- `StrideTests`: **60/60 PASS**, 0 failures, 0 skipped
- No Swift compiler warnings
- Automatic-only source-of-truth model verified end to end, including
  legacy-data migration (old records with manual steps can't qualify
  anything, but their raw historical totals are preserved for display)
- Merged to `main` at commit `cca9edb` — TestFlight upload was **not**
  triggered (merge commit used `[skip ci]` deliberately)

## 8. Files to read first, by task

- **Touching the Figure/animation**: `Shared/Design/AvatarView.swift`,
  `Shared/Design/MotionConfig.swift`
- **Touching movement detection/signals**: `Stride/Logic/StepProvider.swift`,
  `Stride/Logic/MovementClassifier.swift`
- **Touching goal/streak/points/rewards**: `Stride/Models/AppState.swift`,
  `Stride/Logic/StreakEngine.swift`, `Stride/Logic/CreditedSteps.swift`,
  `Stride/Logic/Points.swift`
- **Touching navigation**: `Stride/Navigation/Route.swift`,
  `Stride/Navigation/RootView.swift`
- **Touching copy/voice**: `Stride/Copy/Copy.swift`
- **Touching CI**: `.github/workflows/build.yml` (⚠️ uploads to TestFlight
  on every push to `main` — never push casually) vs.
  `.github/workflows/verify.yml` (build+test only, safe, no signing)
- **Tests**: `StrideTests/` — 7 files, one per pure-logic module. Run via
  `verify.yml`, never `build.yml`.
