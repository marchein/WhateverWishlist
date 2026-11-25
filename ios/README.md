# WhateverWishlist for iOS

Native SwiftUI client for the WhateverWishlist backend: another client next to the web app with the same
features. Requires Xcode 26 or newer; runs on iOS 18 and later and uses Liquid Glass on iOS 26 and the
new iOS 27 controls where available.

## Build and run

Open `Wishlist.xcodeproj` in Xcode, choose the `Wishlist` scheme and a simulator, and run.
To run on a device, put your team into `Config/Local.xcconfig` (see below) instead of picking it in
Xcode's Signing tab – Xcode would write it into the shared project file.

## Configuration

The app connects to `https://wishlist.hein.cx` by default. Settings live in
[`Config/App.xcconfig`](Config/App.xcconfig):

| Setting | Purpose |
| --- | --- |
| `WISHLIST_SERVER_URL` | Backend origin (API, uploads, cached images). |
| `WISHLIST_WEB_URL` | Origin used in share links; defaults to the server. |
| `WISHLIST_BUNDLE_ID`, `DEVELOPMENT_TEAM` | Signing. |
| `WISHLIST_DISPLAY_NAME` | Name on the home screen. |
| `WISHLIST_URL_SCHEME` | Opens lists via `whateverwishlist://s/<token>`. |
| `WISHLIST_ENTITLEMENTS`, `WISHLIST_WEB_HOST` | Associated Domains: Universal Links, Handoff, shared passwords (see below). |

For personal settings copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (ignored by Git);
it overrides `App.xcconfig`. `//` starts a comment in xcconfig files, so write URLs as
`https:/$()/host`. Plain `http` is only allowed for local network addresses, e.g.
`http:/$()/localhost:3000` for a backend running on your Mac.

The version comes from `Config/Version.xcconfig`, which `npm version` in the repository root keeps in
sync with the packages.

## Web integration

The app and the web app share one server, so:

- **Universal Links**: `https://<server>/s/<token>`, `/wishlists` and `/status` open in the app.
- **Handoff**: the open list, the overview and the status page continue in Safari on a Mac or iPad,
  and the other way round.
- **Shared passwords**: logins saved for the web app in Safari or Passwords are offered in the app.
- **Smart App Banner**: Safari on iPhone suggests opening or installing the app. This only works once
  the app is on the App Store.

The first three use the Associated Domains in [`Wishlist/Wishlist.entitlements`](Wishlist/Wishlist.entitlements)
for `WISHLIST_WEB_HOST`. They need a paid developer account; with a free one, set `WISHLIST_ENTITLEMENTS =`
in `Config/Local.xcconfig`. The server opts in with two settings in its `.env` (the API serves
`/.well-known/apple-app-site-association` and the banner tag from them):

```bash
IOS_APP_IDS=<TeamID>.cx.hein.wishlist   # Universal Links, Handoff, shared passwords
IOS_APP_STORE_ID=6835103795             # Smart App Banner
```

Apple's CDN caches the association file, so changes can take up to a day to reach devices. Developer
builds can bypass the cache with `applinks:<host>?mode=developer` together with Settings → Developer →
Associated Domains Development.

## Xcode Cloud (TestFlight)

Release tags (`vX.Y.Z`) build the app on Xcode Cloud and upload it to TestFlight, so `/release`
ships iOS along with the Docker images. [`ci_scripts/ci_post_clone.sh`](ci_scripts/ci_post_clone.sh)
then:

- fails the build when the tag doesn't match `MARKETING_VERSION` in `Config/Version.xcconfig`,
- writes `Config/Local.xcconfig` with the signing team (`WISHLIST_DEVELOPMENT_TEAM`) and Xcode Cloud's
  build number,
- writes the TestFlight "What to Test" notes from the commits since the previous tag.

One-time setup in Xcode (Integrate → Create Workflow…) or in App Store Connect → Xcode Cloud:

1. Product: the `Wishlist` app, repository `marchein/WhateverWishlist`. Grant Xcode Cloud access
   to GitHub when asked.
2. Workflow "Release": project `ios/Wishlist.xcodeproj`, scheme `Wishlist`, Xcode "Latest Release".
3. Environment variable `WISHLIST_DEVELOPMENT_TEAM` = your Team ID (not secret).
4. Start condition: **Tag Changes**, tags beginning with `v`. Manual starts are always possible
   ("Start Build" in Xcode or App Store Connect, pick a branch or tag).
5. Actions: **Test** (scheme `Wishlist`, iOS Simulator, test plan `Wishlist`), then **Archive** (iOS,
   deployment preparation *TestFlight (Internal Testing Only)* or *TestFlight and App Store*).
6. Post-action: **TestFlight Internal Testing** with your tester group.
7. Settings → Build Number: set the next number above existing uploads of the current version (earlier
   manual uploads used `yyyyMMddHHmm`). New versions can start from any number.

Submitting to App Store review stays a manual step in App Store Connect.

## Development

- The Xcode project is generated from [`project.yml`](project.yml) with
  [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or removing files run `xcodegen` in `ios/`
  and commit the regenerated project.
- The app is German or English depending on the iOS language, or the language chosen for the app under
  Settings → Wishlist → Language; there is no in-app switch.
- Texts come from the web app. After changing `frontend/src/app/core/i18n/{en,de}.ts` run
  `node ios/scripts/generate-translations.mjs`. iOS-only texts are in `Wishlist/Core/AppStrings.swift`.
- Unit tests: `xcodebuild test -project ios/Wishlist.xcodeproj -scheme Wishlist -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`.
