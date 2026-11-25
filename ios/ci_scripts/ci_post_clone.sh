#!/bin/sh
# Xcode Cloud runs this after cloning the repository (cwd: ios/ci_scripts). See ios/README.md → Xcode Cloud.
set -eu

IOS_DIR="$CI_PRIMARY_REPOSITORY_PATH/ios"
VERSION=$(sed -n 's/^MARKETING_VERSION = //p' "$IOS_DIR/Config/Version.xcconfig")

# A release tag must match the version that `npm version` wrote, like the Docker workflow checks.
if [ -n "${CI_TAG:-}" ] && [ "$CI_TAG" != "v$VERSION" ]; then
  echo "error: tag $CI_TAG does not match MARKETING_VERSION $VERSION in ios/Config/Version.xcconfig" >&2
  exit 1
fi

# Local.xcconfig is ignored by Git; on Xcode Cloud it carries the signing team and the build number.
{
  echo "// Written by ci_scripts/ci_post_clone.sh"
  if [ -n "${WISHLIST_DEVELOPMENT_TEAM:-}" ]; then
    echo "DEVELOPMENT_TEAM = $WISHLIST_DEVELOPMENT_TEAM"
  fi
  if [ -n "${CI_BUILD_NUMBER:-}" ]; then
    echo "CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER"
  fi
} > "$IOS_DIR/Config/Local.xcconfig"
cat "$IOS_DIR/Config/Local.xcconfig"

# Tester notes for TestFlight: the commits since the previous release tag.
cd "$CI_PRIMARY_REPOSITORY_PATH"
git fetch --tags --quiet 2>/dev/null || true
PREVIOUS=$(git describe --tags --abbrev=0 --match 'v*' HEAD^ 2>/dev/null || true)
mkdir -p "$IOS_DIR/TestFlight"
{
  echo "WhateverWishlist $VERSION"
  echo
  git log --no-merges --pretty='- %s' ${PREVIOUS:+"$PREVIOUS..HEAD"} -n 15
} > "$IOS_DIR/TestFlight/WhatToTest.en-US.txt"
cp "$IOS_DIR/TestFlight/WhatToTest.en-US.txt" "$IOS_DIR/TestFlight/WhatToTest.de-DE.txt"
