# Apple Developer account reference

Reference values for this project's Apple Developer Program enrollment and
App Store Connect setup. Safe to keep in the repo — these are identifiers,
not secrets. The actual private key is **not** here; see below.

## Account

- **Apple ID**: ramlankalapalli99@icloud.com
- **Team ID**: `8H76WJFG65`
- **Enrollment type**: Individual

## App identifiers

Registered under **Certificates, Identifiers & Profiles → Identifiers**:

| App | Bundle ID |
|---|---|
| Stride (main app) | `com.ramlankalapalli.stride` |
| Stride Widget (extension) | `com.ramlankalapalli.stride.widget` |

Note: `com.stride.app` was tried first and rejected — bundle IDs are unique
across *all* Apple developers globally, not just this account, and someone
else already held it. That's why the ID is tied to the username instead.

## App Store Connect

- **App name (internal)**: `Stride RL` — "Stride" alone and "Step Tracker"
  were both already taken as App Store display names. This is cosmetically
  changeable anytime later from App Store Connect → App Information; it does
  not affect the bundle ID or anything technical.
- **SKU**: `stride001`

## CI signing (App Store Connect API key)

Used by `.github/workflows/build.yml` to sign and upload builds to
TestFlight automatically — no manual certificates or provisioning profiles.

- **Key name**: `CI`
- **Key ID**: `8NG7HMH9UY`
- **Issuer ID**: `02f3f3fe-8be1-4a55-b816-a037ad8f75e8`
- **Access level**: App Manager

### Where the actual private key lives

The downloaded file (`AuthKey_8NG7HMH9UY.p8`) is **never committed to this
repo**. It exists in exactly two places:
1. This laptop's `Downloads` folder (the original download — Apple only
   allows downloading it once, so this copy is the only backup outside
   GitHub)
2. The GitHub repo secret `APP_STORE_CONNECT_API_KEY_P8`, which the CI
   workflow reads at build time

If the key is ever lost or needs rotating: App Store Connect → Users and
Access → Integrations → App Store Connect API → revoke the old key, generate
a new one, and update the four GitHub secrets below to match.

### GitHub repo secrets (already set)

| Secret | Value |
|---|---|
| `APP_STORE_CONNECT_API_KEY_P8` | contents of the `.p8` file |
| `APP_STORE_CONNECT_KEY_ID` | `8NG7HMH9UY` |
| `APP_STORE_CONNECT_ISSUER_ID` | `02f3f3fe-8be1-4a55-b816-a037ad8f75e8` |
| `APPLE_TEAM_ID` | `8H76WJFG65` |

## Capabilities

None enabled yet on either App ID — HealthKit, Sign in with Apple, push
notifications, and App Groups were all skipped during registration to keep
the first build simple. See the `TODO(open)` note in `project.yml` for what
to re-enable later and where.
