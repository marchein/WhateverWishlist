# WhateverWishlist

Monorepo: `backend/` (API), `frontend/` (Angular), `ios/` (Xcode app), `scripts/` (version sync).
Node 24 (`.nvmrc`). Images are published to `ghcr.io/marchein/whateverwishlist-{api,web}`.

## Shared agent instructions

The release workflow lives in [.github/skills/release/SKILL.md](.github/skills/release/SKILL.md)
(originally written for GitHub Copilot) and is linked into `.claude/skills/release`, so `/release`
uses the same procedure. Edit the file under `.github/`, not a copy.

When following it as Claude, end commits with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` instead of the Copilot trailer.

## Commands

```bash
npm run install:all          # root, backend, frontend
npm run dev                  # api + web concurrently
npm test                     # version sync, icons, backend, frontend
npm run lint --prefix frontend
npm run build                # production builds (no budget warnings allowed)
npm run version:check -- v<version>
```

iOS (`ios/`, SwiftUI, Xcode 27 SDK; project generated from `ios/project.yml`):

```bash
cd ios && xcodegen                                  # after adding/removing Swift files
node ios/scripts/generate-translations.mjs          # after changing frontend i18n (en.ts/de.ts)
xcodebuild test -project ios/Wishlist.xcodeproj -scheme Wishlist \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WishlistTests
```

UI tests (`WishlistUITests`) run against the in-app mock backend; `UITEST_ANIMATIONS=1` and
`UITEST_LATENCY_MS` make performance tests realistic.

## Rules

- Versions: bump only via `npm version <x.y.z> --no-git-tag-version` (root hook syncs all manifests).
- Never commit `.env`, `backend/data/`, or `.vscode/settings.json`.
- Branch naming: `<type>/<short-topic>-<version>`, PRs merged with a merge commit.
