# Getting Stride onto your iPhone — via TestFlight

This project moved off the free AltStore/AltServer sideloading path (fought
Windows driver conflicts for a while — see git history if curious) to proper
TestFlight distribution instead. Requires the paid Apple Developer Program
($99/year, already enrolled — see `APPLE_DEVELOPER.md` for account details).

## One-time setup (already done)

1. Apple Developer Program enrollment
2. Two App IDs registered (`com.ramlankalapalli.stride` and
   `.widget`) — see `APPLE_DEVELOPER.md`
3. App created in App Store Connect (`Stride RL`)
4. App Store Connect API key generated, stored as GitHub secrets
5. `.github/workflows/build.yml` signs and uploads automatically on every
   push to `main`

Nothing above needs repeating unless the API key gets revoked/rotated.

## Every time there's a new build

1. Push to `main` (or trigger manually: Actions tab → "Build and publish to
   TestFlight" → *Run workflow*)
2. GitHub Actions builds, signs, and uploads to TestFlight automatically —
   takes a few minutes
3. Apple processes the build (usually a few minutes, occasionally longer the
   first time)
4. On the iPhone: open **TestFlight** (install it from the App Store first if
   it isn't already there) → **Stride RL** shows up under your apps →
   tap **Install** or **Update**

No cable, no AltServer, no laptop needed for this part at all — TestFlight
pulls directly from Apple's servers.

## If a build fails

Check the failing run's **Summary** page on GitHub (Actions tab → the red ✗
run) — the workflow prints the actual compiler/signing error there directly,
since raw Action logs require being signed into GitHub to view.

## Adding capabilities back later

HealthKit, push notifications, Sign in with Apple, and App Groups (for the
widget) were all skipped when registering the App IDs, to keep the first
build simple. To add any of them back:

1. App Store Connect (or developer.apple.com) → Identifiers → edit the
   relevant App ID → enable the capability
2. Uncomment/re-add the matching entries in `Stride/Stride.entitlements` (or
   `StrideWidget/StrideWidget.entitlements`) and the `entitlements:
   properties:` block in `project.yml` — see the `TODO(open)` comment there
   for what was removed
3. Push — the next build will pick up the new capability automatically
   (`-allowProvisioningUpdates` regenerates the provisioning profile to
   match)
