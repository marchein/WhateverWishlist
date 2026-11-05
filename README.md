# WhateverWishlist

[![Latest push CI status](https://github.com/marchein/WhateverWishlist/actions/workflows/docker.yml/badge.svg?event=push)](https://github.com/marchein/WhateverWishlist/actions/workflows/docker.yml?query=event%3Apush)
[![Latest tag](https://img.shields.io/github/v/tag/marchein/WhateverWishlist?label=latest%20tag)](https://github.com/marchein/WhateverWishlist/tags)
[![Node.js 24](https://img.shields.io/badge/Node.js-24-339933?logo=nodedotjs&logoColor=white)](#development-and-contributing)
[![100% AI-generated](https://img.shields.io/badge/AI--generated-100%25-8A2BE2)](#-ai-generated-project)

CI status reflects the latest push workflow run across branches, including tests, lint and builds.
The version badge shows the latest Git tag, not a GitHub Release.

<img src="./frontend/src/assets/icon/app-icon.svg" width="80" alt="WhateverWishlist gift icon" />

A self-hosted wishlist for wishes from any shop. Share one link with friends and family:
they can mark gifts as bought, while purchases stay hidden from the logged-in owner.
Runs in any browser and can be installed to the home screen as a web app (PWA).

**Start here:** [Deploy](#deploy-with-docker) · [Update](#update-or-roll-back) ·
[Manage users](#command-line-administration) · [Back up](#back-up-and-restore) ·
[Contribute](#development-and-contributing) · [Publish a release](#build-and-publish-on-github) · [Install the app](#install-as-an-app)

## 🤖 AI-generated project

The code in this repository is **100% AI-generated**. I (@marchein) act as the
directing developer: I define the requirements, review every change, test the
results, and decide what ships — but I did not hand-write the implementation.
Treat it accordingly and review before deploying anything to production.

## Deploy with Docker

Requires Docker Engine with the Compose plugin, a domain, and an HTTPS reverse proxy.
The server only needs the Compose file and configuration, not the source code.

```bash
mkdir -p ~/wishlist && cd ~/wishlist
curl -fsSLO https://raw.githubusercontent.com/marchein/wishlist/main/docker-compose.yml
curl -fsSL -o .env https://raw.githubusercontent.com/marchein/wishlist/main/.env.example
openssl rand -base64 48
nano .env
```

Paste the generated secret into `JWT_SECRET` and set `PUBLIC_URL` to your actual HTTPS address.
Never commit the real `.env`.

| Setting | Purpose |
| --- | --- |
| `JWT_SECRET` | Required; at least 32 characters. Keep it stable: changing it signs everyone out. |
| `PUBLIC_URL` | Public origin, e.g. `https://wishlist.example.com`; used in messenger previews. |
| `WISHLIST_PORT` | Host binding; use `127.0.0.1:8080` with a reverse proxy on the same host. |
| `TRUST_PROXY` | `2` for web container + HTTPS proxy; `1` when only the web container is in front of the API. |
| `CORS_ORIGINS` | Additional allowed origins; usually empty because the web app is served from the same origin. |
| `SCRAPER_ACCEPT_LANGUAGE` | Language requested from shops when reading product pages. |
| `IMAGE_CACHE_DIR` | Directory to store cached images; default `data/image-cache`. Relative to the data volume. |
| `IMAGE_CACHE_MAX_SIZE` | Maximum cache size in bytes; default `209715200` (200 MB). Examples: `104857600` (100 MB), `524288000` (500 MB), `1073741824` (1 GB). |
| `IMAGE_CACHE_MAX_AGE` | Days before deleting unused cached images; default `30`. |

If the GitHub container packages are private, first run `docker login ghcr.io -u YOUR_GITHUB_USERNAME`
and enter a token with `read:packages` permission. Public packages do not require login.

```bash
docker compose pull
docker compose up -d --no-build
docker compose ps
docker compose logs --tail=100
```

Both services should become healthy:

| Service | Image | Responsibility |
| --- | --- | --- |
| `web` | `ghcr.io/marchein/wishlist-web:latest` | Serves the frontend and proxies API requests; host port 8080. |
| `api` | `ghcr.io/marchein/wishlist-api:latest` | Backend, SQLite database and uploads; not exposed directly. |

For example, put this behind [Caddy](https://caddyserver.com), which handles HTTPS certificates:

```caddyfile
wishlist.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

Open your public address and create an account. Check `/api/health` for backend health/version,
or **App status** (`/status`) for the installed frontend version and connected backend version/address.

For a local, non-HTTPS trial, set `WISHLIST_PORT=8080`, `PUBLIC_URL=http://localhost:8080`
and `TRUST_PROXY=1`, then open `http://localhost:8080`.

## Update or roll back

Make a [backup](#back-up-and-restore) before upgrading. In the directory containing your deployed
Compose file and `.env`:

```bash
docker compose pull
docker compose up -d --no-build
docker compose ps
```

Then reload the web app and check **App status**. Installed home-screen apps load the new version
from the server as well.

- `latest` follows the newest tagged release.
- To pin or roll back, change **both** image tags in [docker-compose.yml](docker-compose.yml)
  to the same release, e.g. `:1.0.3`, then run the commands above.
- Database migrations run automatically. Rolling back an image does not reverse migrations;
  restore the matching pre-upgrade backup if an older release cannot use the upgraded database.
- `docker compose down` stops the stack without deleting data. **Do not use `down -v`** unless
  you intend to delete the database and uploaded images.

## Command-line administration

These are **local operator commands**, not public HTTP endpoints. Anyone able to run commands in the API
container already has administrative access to the database. Run these from your deployment directory.

### List every user and their wishlists

```bash
docker compose exec -T api node dist/admin-cli.js users
```

The JSON output includes each user's ID, email, display name and creation time, with all their wishlists
(IDs, titles, descriptions, dates, item counts and timestamps). Users without wishlists have an empty
array. Passwords, password hashes, login tokens, share tokens and purchase information are not included.
Treat the output as personal data.

### Reset a user's password

```bash
docker compose exec api node dist/admin-cli.js reset-password person@example.com
```

Enter the new password twice at the **hidden prompt**. Email lookup is case-insensitive.
The password must have at least 8 characters and at most 72 UTF-8 bytes, just like registration.

A successful reset:

- Replaces the password hash and signs that user out on **all devices**.
- Does not affect other users, wishlists, purchases or existing public share links.
- Requires the user to log in again with their new password.

For automation, supply exactly one password line through stdin from a protected secret source:

```bash
docker compose exec -T api node dist/admin-cli.js reset-password person@example.com --stdin < /secure/path/new-password.txt
```

The final newline is optional. Do not put passwords in command arguments, shell history or committed
files. Protect and remove any temporary password file. Invalid input or an unknown user exits nonzero
without changing the account. Interactive prompts require a TTY, so omit `-T` for interactive resets.

```bash
docker compose exec -T api node dist/admin-cli.js --help
```

For local development, the equivalent is `npm run admin --prefix backend -- users` or
`npm run admin --prefix backend -- reset-password person@example.com`. The configured database must
already exist; the CLI will not silently create an empty one.

### Cache external images locally

```bash
docker compose exec -T api node dist/admin-cli.js cache-images
```

Downloads and optimizes all external images from product shops and caches them on your server.
This reduces dependency on third-party servers and improves performance. The command:

- Automatically optimizes images to progressive JPEG with 75% quality
- Skips images that are already cached or already stored locally
- Respects cache size limits (default: 200 MB; configured via `IMAGE_CACHE_MAX_SIZE`)
- May take a long time if you have many items with external images

The original image URLs stay in the database; caching is completely transparent to the web app.
Once cached, images are served from `/_cache/<hash>` with immutable cache headers (1 year).

For local development:

```bash
npm run admin --prefix backend -- cache-images
```

### Recover corrupted image URLs

If items have cache URLs (`/_cache/<hash>`) instead of original URLs in the database, run the recovery tool:

```bash
docker compose exec api node dist/admin-recover-images.js
```

This interactive tool guides you through:

- Automatically restoring URLs from the cache manifest (if available)
- Manually entering original URLs for items not in the manifest
- Updating the database and manifest in sync

This should not happen with the current version; if it does, ensure all containers are running
the latest code:

```bash
docker compose pull
docker compose up -d --no-build
```

For local development:

```bash
npm run admin --prefix backend -- recover-images
```

Or use `npx tsx src/admin-recover-images.ts` if the `admin` script is not available.

## Back up and restore

The default Compose project stores the database and uploads in the **`wishlist_data`** volume.
If you override the Compose project name, adjust the volume name below.

Stop API writes while archiving the entire volume, including SQLite's WAL files:

```bash
docker compose stop api
docker run --rm -v wishlist_data:/data:ro -v "$PWD:/backup" alpine \
  tar czf /backup/wishlist-$(date +%F).tgz -C /data .
docker compose start api
```

Keep the archive and a secure copy of `.env` off the server. They contain private data and secrets.
If archiving fails, restart the API before troubleshooting.

To restore, stop the API, prepare an **empty** data volume, and extract the chosen archive:

```bash
docker run --rm -v wishlist_data:/data -v "$PWD:/backup:ro" alpine \
  tar xzf /backup/wishlist-YYYY-MM-DD.tgz -C /data
docker compose start api
```

Verify health, account access and uploads after restoring. Do not extract an old backup over a live database.

## Development and contributing

Requires **Node 24** and npm; `.nvmrc` selects the supported version.

Frontend TypeScript stays on the latest 6.0.x release because Angular 22,
Ionic's Angular toolkit and typescript-eslint do not yet support TypeScript 7.
The backend uses TypeScript 7 independently.

Stop the development server before installing or updating dependencies, then restart
`npm run dev`. A running Angular watcher can retain stale package metadata after an update.

```bash
git clone https://github.com/marchein/wishlist.git
cd wishlist
nvm install
nvm use
npm run install:all
npm run dev
```

The frontend runs on `http://localhost:4200`, the API on `http://localhost:3000`.
Backend configuration is in [backend/.env.example](backend/.env.example). Development data, uploads
and an automatically generated JWT secret live under `backend/data/` by default.

```text
backend/src/       Express API, SQLite migrations, scraper, administration CLI and tests
frontend/src/      Ionic + Angular web app
scripts/           Package-version synchronization and release checks
```

Before opening a pull request:

```bash
npm test
npm run lint --prefix frontend
npm run build
```

`npm test` covers version synchronization, generated icon content, frontend behavior, API behavior,
CLI subprocesses, password validation, session revocation and database migration compatibility.
Tests use temporary databases, not development or production data.

Frontend development-tool dependencies `glob` and `minimatch` are pinned through npm overrides
to patched releases for GHSA-3g3m-2fjr-6pw4 and GHSA-g3hv-75wg-m249. These cross-major overrides
are validated with tests, lint and builds; remove them once upstream tools
request patched versions themselves.

- Branch from `main`, keep changes focused, add regression tests, and describe user-visible changes in the PR.
- Keep English and German translations aligned.
- Preserve existing `/s/<token>` links and owner-only editing. Never expose purchase data to authenticated owners.
- Append database migrations; never edit a migration that has already shipped.
- Update this README when operational commands or deployment behavior change.
- Do not commit credentials, real databases, uploads, backups or exported user information.

### Change app artwork

The original source is [app-icon.svg](frontend/src/assets/icon/app-icon.svg). After editing it:

```bash
npm run icons:generate --prefix frontend
npm run test:icons --prefix frontend
```

Commit the regenerated favicon, home-screen and manifest icons together with the source.
Generation uses the development dependency `sharp`; no system image tools are needed.
The tests check dimensions, opacity and actual visible artwork, not just file existence.

To test the complete stack from source:

```bash
cp .env.example .env
# Configure .env as described in the deployment section.
docker compose build
docker compose up -d --no-build
```

## Build and publish on GitHub

The [Docker images workflow](.github/workflows/docker.yml) runs tests, frontend lint, production
builds and a development frontend build on every branch push and release-tag push.
Pull request events do not trigger a separate run, avoiding duplicate checks for branch pushes.
It publishes backend and frontend images for `linux/amd64` and `linux/arm64` only when a
`vMAJOR.MINOR.PATCH` tag is pushed or the workflow is run manually.
It uses the built-in `GITHUB_TOKEN` with package-write permission; no registry secret is needed.

After committing the changes intended for the release, prepare the next version:

```bash
npm version 1.0.4 --no-git-tag-version
npm run version:check -- v1.0.4
npm test
npm run lint --prefix frontend
npm run build
git add package.json package-lock.json backend/package.json backend/package-lock.json frontend/package.json frontend/package-lock.json
git commit -m "Release 1.0.4"
git tag -a v1.0.4 -m "Release 1.0.4"
git push origin main
git push origin v1.0.4
```

The root `npm version` hook synchronizes **all package manifests and lockfiles**. CI rejects a tag
that does not match them. Both the frontend and backend report their own package version.

In GitHub, watch **Actions → Docker images**. A successful tagged run publishes:

```text
ghcr.io/marchein/wishlist-api:1.0.4  :1.0  :1  :latest  :sha-<commit>
ghcr.io/marchein/wishlist-web:1.0.4  :1.0  :1  :latest  :sha-<commit>
```

New GHCR packages may be private. Make them public in their package settings or authenticate on the
deployment host as described above. For forks, the workflow uses your repository's image names;
update the Compose image names accordingly.

For an untagged preview build, use **Actions → Docker images → Run workflow** on the desired branch.
Manual runs publish `sha-<commit>` images but **do not update `latest`**. Pin both Compose images to
that SHA tag to test them. Use a new version/tag for a release; do not move an existing release tag.

## Install as an app

WhateverWishlist is a Progressive Web App; there is no separate native app.

- **iPhone/iPad (Safari):** open your address, tap **Share → Add to Home Screen**.
- **Android/desktop (Chrome, Edge):** open your address and choose **Install app** from the browser menu.

The installed app opens full-screen with its own icon and always uses the version currently
deployed on your server. Icons and name come from
[site.webmanifest](frontend/src/assets/icon/site.webmanifest).

## Sharing and privacy

`/s/<token>` is the normal wishlist address for both owners and recipients: copying the browser
address works. Owners get editing controls; others can mark quantities as bought and undo purchases.
The logged-in owner's API responses omit purchase information, even through the shared address.

Anyone with a share link can access its recipient view without an account. Treat it as a bearer link.
Explicitly regenerating the link or deleting the list invalidates that link; ordinary edits, upgrades
and password resets do not.

Logged-in recipients can follow a shared list from its `/s/<token>` page. Followed lists appear in a
separate section on the start page below the user's own wishlists. Owners can see who follows a list
(display names only) and remove individual followers. When regenerating the share link, the owner
chooses whether followers keep the list (their start page then points to the new link) or are removed.
Removing a follower does not revoke the link itself; regenerate it to do that.

Shop-link import supports common product metadata, with manual entry when a shop blocks access.
Messenger previews include list details and an image, never purchase information.
