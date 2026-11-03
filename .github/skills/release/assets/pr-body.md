## Changes

### <Area, e.g. Follow shared wishlists>
- <User-visible change and why it matters.>
- API: `<METHOD /api/...>` – <what it does>.
- <New database migration: `<table>` (runs automatically).>

### <Further area>
- <Change.>

### Operator notes
- <New/removed environment variables, e.g. "`IOS_APP_IDS` can be removed from `.env`".>
- <Anything to do after `docker compose pull && docker compose up -d --no-build`; "None" if nothing.>

### Release
- All package manifests and lockfiles bumped to **<version>**.

## Validation
- `npm test` (version sync, icons, <n> backend tests, <n> frontend tests), frontend lint, production and development builds pass.
- `npm run version:check -- v<version>` passes.
- <Manual/visual checks performed, e.g. light/dark, desktop/mobile, against a throwaway database.>
