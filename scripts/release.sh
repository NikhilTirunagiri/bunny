#!/bin/bash
# Builds Bunny (Release, ad-hoc signed) and packs it into dist/Bunny-<version>.dmg and dist/Bunny.dmg.
#
#   scripts/release.sh [--publish] [--prerelease] [--allow-dirty]
#
# Without --publish it never touches git remotes or GitHub.
# --publish   tag v<version>, push the tag and create the GitHub release with dist/Bunny.dmg.
#             Needs gh, branch main in sync with origin, and docs/releases/v<version>.md.
# --prerelease  mark the GitHub release as a pre-release (only with --publish).
# --allow-dirty build with uncommitted changes (not allowed with --publish).
set -euo pipefail

PUBLISH=0
PRERELEASE=0
ALLOW_DIRTY=0
for arg in "$@"; do
    case "$arg" in
        --publish) PUBLISH=1 ;;
        --prerelease) PRERELEASE=1 ;;
        --allow-dirty) ALLOW_DIRTY=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

die() { echo "release: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

cd "$(dirname "$0")/.."

PROJECT=bunny.xcodeproj
SCHEME=bunny

VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PROJECT/project.pbxproj" | sort -u)
[ -n "$VERSION" ] || die "MARKETING_VERSION not found in $PROJECT"
[ "$(printf '%s\n' "$VERSION" | wc -l | tr -d ' ')" = 1 ] || die "MARKETING_VERSION differs between configurations: $(echo $VERSION)"
TAG="v$VERSION"
NOTES="docs/releases/$TAG.md"

if [ "$ALLOW_DIRTY" = 1 ] && [ "$PUBLISH" = 1 ]; then
    die "--allow-dirty cannot be used with --publish"
fi
if [ "$PRERELEASE" = 1 ] && [ "$PUBLISH" = 0 ]; then
    die "--prerelease only makes sense with --publish"
fi
if [ -n "$(git status --porcelain)" ] && [ "$ALLOW_DIRTY" = 0 ]; then
    die "the git tree has uncommitted changes (commit them, or pass --allow-dirty for a local build)"
fi

# Everything --publish needs is checked before the build, so it fails early.
if [ "$PUBLISH" = 1 ]; then
    command -v gh >/dev/null || die "gh is not installed"
    [ -f "$NOTES" ] || die "release notes not found: $NOTES"
    [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "releases are published from main"
    git fetch --quiet --tags origin main
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main is not in sync with origin/main"
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then die "tag $TAG already exists"; fi
    if [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then die "tag $TAG already exists on origin"; fi
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/bunny-release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

step "Bunny $VERSION: swift test"
swift test

step "xcodebuild (Release, universal, ad-hoc signed)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$WORK/dd" -quiet CODE_SIGN_IDENTITY=- build

BUILT="$WORK/dd/Build/Products/Release/bunny.app"
[ -d "$BUILT" ] || die "the build produced no app at $BUILT"
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT/Contents/Info.plist")
[ "$BUILT_VERSION" = "$VERSION" ] || die "the built app is version $BUILT_VERSION, expected $VERSION"

step "Disk image"
STAGE="$WORK/stage"
mkdir -p "$STAGE" dist
ditto "$BUILT" "$STAGE/Bunny.app"
codesign --verify --deep --strict "$STAGE/Bunny.app" || die "the staged app's signature does not verify"
ln -s /Applications "$STAGE/Applications"

DMG="dist/Bunny-$VERSION.dmg"
hdiutil create -quiet -ov -volname Bunny -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
cp -f "$DMG" dist/Bunny.dmg

echo "$DMG"
echo "dist/Bunny.dmg (same file, the name the README links to)"
echo "size:    $(stat -f %z "$DMG") bytes ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
echo "sha-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"

if [ "$PUBLISH" = 0 ]; then
    printf '\nNot published. To publish: scripts/release.sh --publish\n'
    exit 0
fi

step "Publishing $TAG"
git tag -a "$TAG" -m "Bunny $TAG"
git push origin "$TAG"
PRERELEASE_FLAG=""
[ "$PRERELEASE" = 1 ] && PRERELEASE_FLAG="--prerelease"
# shellcheck disable=SC2086
gh release create "$TAG" dist/Bunny.dmg --title "Bunny $TAG" --notes-file "$NOTES" $PRERELEASE_FLAG
