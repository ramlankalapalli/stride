# Getting Stride onto your iPhone — no Mac required

Free path: GitHub builds it, AltStore puts it on your phone. ~15 minutes the
first time, automatic after that.

## One-time setup

1. **Push this folder to a GitHub repo** (if it isn't already):
   ```bash
   git init
   git add .
   git commit -m "Stride: initial scaffold"
   git remote add origin https://github.com/<you>/stride.git
   git push -u origin main
   ```
2. **On your iPhone**: install the AltStore app.
   - Go to `altstore.io` in Safari on the phone, follow their installer — it
     walks you through trusting the AltStore profile in Settings.
3. **On this Windows laptop**: install **AltServer** from the same site
   (`altstore.io` → Windows download). Run it — it sits in the system tray.
4. **Connect the two**: plug the iPhone into this laptop with a USB cable (or
   put both on the same Wi-Fi network), then in AltServer's tray icon choose
   *Install AltStore* → select your iPhone. It'll ask for your **Apple ID** —
   any free Apple ID works, this is not the paid developer program. AltServer
   uses it to get you a free, personal signing certificate.

## Every time you want a new build on your phone

1. **Get the build**: after a push to `main`, GitHub Actions runs
   automatically (check the *Actions* tab of the repo). When it's green,
   open the run → download the `Stride-unsigned` artifact → unzip it to get
   `Stride.ipa`.
   - Or trigger it manually: Actions tab → "Build sideloadable IPA" →
     *Run workflow*.
2. **Install it**: with AltServer running in the tray and the phone
   connected, right-click the tray icon → *Install .ipa* → pick the phone →
   select `Stride.ipa`. It signs and pushes it over in under a minute.
3. Open the app on the phone like any other app.

## The 7-day catch

Apple's free signing certificates expire weekly. AltStore refreshes the app
automatically in the background *as long as AltServer is running on this
laptop and the phone is reachable* (USB or same Wi-Fi) at least once every
7 days. If a week passes with the laptop off, open AltStore on the phone and
tap *Refresh* once it can see AltServer again.

## If the build fails at the signing step

HealthKit, Sign in with Apple, and push notifications are entitlements Apple
normally gates behind the paid $99/year developer program, even for
sideloading. If AltServer errors out specifically on one of those:
- Quick fix: comment out that entitlement in `Stride/Stride.entitlements` and
  rebuild — Core Motion step counting, the whole UI, and local data don't need
  any of them.
- Real fix: enroll in the Apple Developer Program later and switch to proper
  TestFlight distribution — no code changes needed, just different signing.
