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
| `WISHLIST_ENTITLEMENTS`, `WISHLIST_WEB_HOST` | Optional Universal Links (see below). |

For personal settings copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (ignored by Git);
it overrides `App.xcconfig`. `//` starts a comment in xcconfig files, so write URLs as
`https:/$()/host`. Plain `http` is only allowed for local network addresses, e.g.
`http:/$()/localhost:3000` for a backend running on your Mac.

The version comes from `Config/Version.xcconfig`, which `npm version` in the repository root keeps in
sync with the packages.

## Universal Links (optional)

To open `https://<server>/s/<token>` links directly in the app, set `WISHLIST_ENTITLEMENTS =
Wishlist/Wishlist.entitlements`, set `WISHLIST_WEB_HOST`, and serve an `apple-app-site-association`
file for your team and bundle ID from the web server. Without that, links open in the browser, and
can be pasted into the app via "Open a shared wishlist".

## Development

- The Xcode project is generated from [`project.yml`](project.yml) with
  [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or removing files run `xcodegen` in `ios/`
  and commit the regenerated project.
- The app is German or English depending on the iOS language, or the language chosen for the app under
  Settings → Wishlist → Language; there is no in-app switch.
- Texts come from the web app. After changing `frontend/src/app/core/i18n/{en,de}.ts` run
  `node ios/scripts/generate-translations.mjs`. iOS-only texts are in `Wishlist/Core/AppStrings.swift`.
- Unit tests: `xcodebuild test -project ios/Wishlist.xcodeproj -scheme Wishlist -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`.
