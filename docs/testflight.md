# TestFlight upload (TRIP-36)

How a build gets from this repo to TestFlight. There is no CI upload; whoever uploads follows these steps on a Mac
signed in to the Apple Developer team `PHVU622P3U`. Apple account work (App Store Connect, privacy answers, testers)
is Taylor's.

## Once: App Store Connect

1. **Xcode › Settings › Accounts:** add the Apple ID that belongs to team `PHVU622P3U`.
2. **App Store Connect › Apps:** the TripSplit record exists (Apple ID `6818893346`, bundle ID `com.taylor.tripsplit`).
3. **TestFlight › Test Information:** a beta description (what to try) and a feedback email.
4. **App Privacy:** the nutrition label. Settled answers: no tracking; Name and User ID are collected, linked to the
   user, for App Functionality; no phone number, no contacts, no location. Still Taylor's to answer, not settled here:
   - the Venmo username (don't assume it's Apple's "Payment Info");
   - the email address Sign in with Apple may share with Supabase.
   If the label gains a type, add it to `ios/TripSplit/PrivacyInfo.xcprivacy` too so the two agree.
5. **TestFlight › Internal Testing:** a group with Taylor and Atish. The external group for the five friends is
   TRIP-37, not this step.

## Each upload

1. Bump the build number: `CURRENT_PROJECT_VERSION` in `ios/project.yml` (App Store Connect rejects a number it has
   already seen for this version). Change `MARKETING_VERSION` only for a new version (`0.1.0` today). Commit it.
2. In `ios/`, run `xcodegen`, then open `TripSplit.xcodeproj`.
3. Destination **Any iOS Device (arm64)**, then **Product › Archive**. Archive builds Release, which talks to the
   hosted Supabase project.
4. In the Organizer: **Distribute App › TestFlight & App Store** (or **TestFlight Internal Only**) › Distribute.
   Automatic signing creates the distribution certificate and profile the first time.
5. Wait for App Store Connect to finish processing (email, usually 10–30 minutes). Export compliance is already
   answered: `ITSAppUsesNonExemptEncryption` is `NO` in `project.yml` (HTTPS only).
6. Testers install from the TestFlight app. Profile's footer shows `TripSplit 0.1.0 (n)`, matching the upload.

Before the first upload, **Organizer › the archive › Generate Privacy Report** should list TripSplit's own manifest
(UserDefaults, reason `CA92.1`; Name and User ID) plus swift-crypto's, which ships its own. Don't copy package
reasons into the app's manifest.

## Push on TestFlight

`ios/TripSplit/TripSplit.entitlements` says `aps-environment` `development` and stays that way: Xcode installs need
it, and the App Store / TestFlight export rewrites it to `production`. TestFlight tokens are production tokens. The
sender tries production first and falls back to sandbox only on `400 BadDeviceToken` (`docs/push-setup.md`), so
nothing on the server changes.

Check on a TestFlight install: sign in, allow notifications, have the other phone add an expense you're in, and
confirm the push arrives. An agent can't close this check.
