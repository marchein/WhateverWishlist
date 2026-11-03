---
name: release
description: 'Ship pending changes as a new WhateverWishlist release: bump the version, branch, commit, open and merge the pull request, then push the vX.Y.Z tag that publishes the Docker images. Use when asked to release, publish, cut/tag a version, "make this a 1.x.y", create a PR and merge it, or ship to GHCR.'
argument-hint: 'Version to release, e.g. 1.3.0 (optional; derived from the changes if omitted)'
---

# Release WhateverWishlist

End-to-end flow from uncommitted work on `main` to published images on GHCR.
It mirrors how releases v1.1.x–v1.2.0 were shipped: feature branch → PR with a merge commit →
annotated tag on the merge commit → the [Docker images workflow](../../workflows/docker.yml)
publishes `ghcr.io/marchein/whateverwishlist-{api,web}`.

## When to Use

- "Make this a 1.2.0", "release this", "tag a new version", "create the PR and release it"
- Any request to commit, open a PR, merge it **and** publish a version in one go

Do **not** use for commits or PRs without a release; follow only the relevant steps then.

## Rules

- Each step depends on the previous one succeeding. Stop and report on any failure instead of
  working around it (no `--no-verify`, no force-push, no moving existing tags).
- Never commit secrets, `.env`, `backend/data/` (databases, uploads, `jwt-secret`) or local editor
  settings such as `.vscode/settings.json`. Review `git status` before staging.
- There are no GitHub Releases: the tag alone is the release (see README badge note).
  Don't create one unless asked.
- Commits end with the trailer
  `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.

## Procedure

### 1. Check the README

Compare the README with the pending diff (`git --no-pager diff --stat`, then the relevant hunks):
new features, removed features, configuration (`.env.example`), commands, deployment notes.
Update it in the same release if anything is outdated.

### 2. Choose the version

Semantic versioning against the latest tag (`git tag --sort=-v:refname | head -1`):
new features → minor, fixes only → patch, breaking deployment changes → major.
Use the version the user named if they gave one.

### 3. Branch and bump

```bash
git switch -c <type>/<short-topic>-<version>     # e.g. feat/followed-wishlists-1.2.0, fix/mobile-ui-1.1.1
npm version <version> --no-git-tag-version       # root hook syncs all manifests and lockfiles
npm run version:check -- v<version>
```

### 4. Run the full CI chain locally

All must pass before committing:

```bash
npm test                                         # version sync, icons, backend, frontend
npm run lint --prefix frontend
npm run build
npm run build --prefix frontend -- --configuration development
```

The production build must not print budget warnings. Frontend tooling needs Node 24 (`.nvmrc`).

### 5. Commit

Stage everything intended, explicitly excluding local-only files:

```bash
git add -A -- . ':!.vscode/settings.json'
git status --short                               # verify: only intended changes, nothing sensitive
```

Commit message (write it to a temp file and use `git commit -F`):

```text
<type>: <summary> (v<version>)

<Area>
- <user-visible change>
- <API / migration / config change>

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

### 6. Push and open the pull request

```bash
git push -u origin <branch>
gh pr create --base main --head <branch> --title "<commit summary>" --body-file <tmp>/pr-body.md
```

Fill the body from the [PR template](./assets/pr-body.md): changes grouped by area, required
operator actions (new env vars, removed settings, migrations), and the validation performed.

### 7. Wait for CI, then merge

```bash
RUN=$(gh run list --branch <branch> --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN" --exit-status --interval 20
gh pr view <number> --json mergeable,mergeStateStatus   # expect MERGEABLE / CLEAN
gh pr merge <number> --merge --delete-branch             # merge commit, as in previous releases
git switch main && git pull --ff-only
npm run version:check -- v<version>
```

On the branch run, `test` must succeed and `publish` is expected to be skipped.

### 8. Tag and publish

Tag the merge commit on `main` and push only that tag:

```bash
git tag -a v<version> -m "Release <version>" <merge-commit-sha>
git push origin v<version>
RUN=$(gh run list --event push --limit 5 --json databaseId,headBranch \
  -q '[.[] | select(.headBranch=="v<version>")][0].databaseId')
gh run watch "$RUN" --exit-status --interval 30
gh run view "$RUN" --json conclusion,jobs -q '.conclusion, (.jobs[] | "\(.name): \(.conclusion)")'
```

Expect `test`, `publish (api, backend)` and `publish (web, frontend)` to succeed. CI rejects the
tag if it doesn't match the package versions.

### 9. Report

Summarize for the user: version, branch, commit, PR link, merge commit, tag, workflow result and
published image tags (`<version>`, `<major>.<minor>`, `<major>`, `latest`, `sha-<commit>`), plus
operator follow-ups (e.g. `docker compose pull && docker compose up -d --no-build`, `.env` changes).
Remove temporary message/body files.
