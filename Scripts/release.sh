#!/usr/bin/env bash
#
# Publishes the newest version in CHANGELOG.md as a GitHub release: checks → swift test →
# Scripts/build-app.sh --zip → tag vX.Y.Z → push master and the tag → gh release with the
# zip and the version's CHANGELOG section as notes.
#
# Before running it, move the [Unreleased] entries in CHANGELOG.md into a new
# "## [X.Y.Z] - YYYY-MM-DD" section, add its link at the bottom, and commit.
#
# Needs the "Mousecape Code Signing" certificate (Scripts/make-signing-certificate.sh), so
# every release carries the same signature, and gh logged in to GitHub.
#
# Usage:
#   Scripts/release.sh          # asks before tagging and publishing
#   Scripts/release.sh --yes    # doesn't ask
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }

VERSION="$(sed -n 's/^## \[\([0-9][0-9.]*\)\] - .*/\1/p' CHANGELOG.md | head -n 1)"
[ -n "$VERSION" ] || die "no released version in CHANGELOG.md"
TAG="v$VERSION"

echo "==> Checks for $TAG…"
[ "$(git branch --show-current)" = "master" ] || die "not on master"
[ -z "$(git status --porcelain)" ] || die "the working tree has uncommitted changes"
git fetch --quiet origin
[ "$(git rev-list --count HEAD..origin/master)" = "0" ] || die "origin/master has commits that are not here"
! git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null || die "tag $TAG exists already"
! git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null || die "tag $TAG exists on origin"
grep -q "^\[$VERSION\]: " CHANGELOG.md || die "CHANGELOG.md has no link for [$VERSION]"
security find-certificate -c "Mousecape Code Signing" >/dev/null 2>&1 \
    || die "no \"Mousecape Code Signing\" certificate (run Scripts/make-signing-certificate.sh)"
gh auth status >/dev/null 2>&1 || die "gh is not logged in"

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
# The version's section, without its heading, up to the next version or the links.
awk -v heading="## [$VERSION]" '
    index($0, heading) == 1 { found = 1; next }
    found && (/^## \[/ || /^\[[^]]+\]: /) { exit }
    found { print }
' CHANGELOG.md > "$NOTES"
grep -q '[^[:space:]]' "$NOTES" || die "the CHANGELOG section for $VERSION is empty"
cat >> "$NOTES" <<'EOF'

### Installing

Unzip, move Mousecape.app to Applications, and run once in Terminal:

```
xattr -cr /Applications/Mousecape.app
```

The app is signed with a self-signed certificate, not notarized by Apple, so macOS blocks
it until then. Requires macOS 14 or later on Apple silicon.

Mousecape is free for personal, non-commercial use only; see [LICENSE](LICENSE).
EOF
# Relative links (CHANGES.md, LICENSE) don't resolve in release notes: point them at the tag.
REPO_URL="https://github.com/Metal-Snake/Mousecape"
sed -i '' -E "s#\]\(([A-Za-z0-9_./-]+)\)#](${REPO_URL}/blob/${TAG}/\1)#g" "$NOTES"

echo "==> Tests…"
swift test

Scripts/build-app.sh --zip
ASSET="$ROOT/dist/Mousecape-$VERSION.zip"
mv "$ROOT/dist/Mousecape.app.zip" "$ASSET"

if [ "${1:-}" != "--yes" ]; then
    read -r -p "Tag and publish $TAG? [y/N] " answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ] || die "cancelled"
fi

echo "==> Tag and push…"
git tag -a "$TAG" -m "Mousecape $VERSION"
git push origin master "$TAG"

echo "==> GitHub release…"
gh release create "$TAG" "$ASSET" --verify-tag --title "Mousecape $VERSION" --notes-file "$NOTES"
