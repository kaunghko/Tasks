#!/usr/bin/env bash
# Builds, signs, notarizes and publishes a release of K2Tasks, then updates the Sparkle appcast
# so installed copies offer the update.
#
#   scripts/release.sh 0.2.0
#
# One-time setup is in README.md ▸ Releasing. No secrets live in this repo: the notarization
# password is in the "TasksNotary" Keychain profile, and Sparkle's EdDSA private key is in the
# login Keychain, where Sparkle's generate_keys put it.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version, e.g. 0.2.0>}"
REPO="kaunghko/Tasks"
NOTARY_PROFILE="TasksNotary"
SPARKLE_VERSION="2.10.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/release"
PBXPROJ="$ROOT/Tasks.xcodeproj/project.pbxproj"
cd "$ROOT"

fail() { echo "error: $*" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3"
[[ -z "$(git status --porcelain)" ]] || fail "commit or stash your changes first"
[[ "$(git branch --show-current)" == main ]] || fail "release from main"
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || fail "v$VERSION already exists"
command -v gh >/dev/null || fail "install the GitHub CLI: brew install gh && gh auth login"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "no '$NOTARY_PROFILE' notarization profile in the Keychain (see README ▸ Releasing)"

# Sparkle's command-line tools, cached in the ignored build folder.
SPARKLE_BIN="$ROOT/build/sparkle-$SPARKLE_VERSION/bin"
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  mkdir -p "$ROOT/build/sparkle-$SPARKLE_VERSION"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$ROOT/build/sparkle-$SPARKLE_VERSION"
fi

# Sparkle compares build numbers, so every release gets the next one.
OLD_BUILD=$(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$PBXPROJ" | grep -oE '[0-9]+$')
BUILD_NUMBER=$((OLD_BUILD + 1))
sed -i '' -E \
  -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/" \
  -e "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/" \
  "$PBXPROJ"
trap 'git checkout -- "$PBXPROJ" appcast.xml 2>/dev/null || true' ERR

echo "==> Testing"
xcodebuild test -scheme Tasks -destination 'platform=macOS' -quiet

echo "==> Archiving $VERSION ($BUILD_NUMBER)"
rm -rf "$BUILD" && mkdir -p "$BUILD/updates"
xcodebuild archive -scheme Tasks -configuration Release \
  -archivePath "$BUILD/Tasks.xcarchive" -allowProvisioningUpdates -quiet
xcodebuild -exportArchive -archivePath "$BUILD/Tasks.xcarchive" \
  -exportPath "$BUILD/export" -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" \
  -allowProvisioningUpdates -quiet
APP="$BUILD/export/K2Tasks.app"

echo "==> Notarizing"
ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
xcrun notarytool submit "$BUILD/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

echo "==> Updating appcast"
ZIP="K2Tasks-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD/updates/$ZIP"
if [[ -f appcast.xml ]]; then cp appcast.xml "$BUILD/updates/"; fi
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  "$BUILD/updates"
cp "$BUILD/updates/appcast.xml" appcast.xml

echo "==> Publishing"
git add "$PBXPROJ" appcast.xml
git commit -m "Release $VERSION"
git tag "v$VERSION"
trap - ERR
# Push the tag and upload the zip before moving main, so the appcast on main never
# points at a download that doesn't exist yet.
git push origin "v$VERSION"
gh release create "v$VERSION" "$BUILD/updates/$ZIP" --repo "$REPO" --title "K2Tasks $VERSION" --generate-notes
git push origin main

echo "Released K2Tasks $VERSION: https://github.com/$REPO/releases/tag/v$VERSION"
