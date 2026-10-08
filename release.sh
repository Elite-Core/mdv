#!/bin/sh
# ./release.sh 1.1 "What changed"
# Builds + notarizes, bumps the build number, tags, pushes, and publishes a GitHub release
# with mdv.zip and latest.json (the update feed). Installed copies see it on their next check.
set -e
cd "$(dirname "$0")"
. ./release.conf
VER="$1"; NOTES="${2:-mdv $1}"
[ -n "$VER" ] || { echo "usage: ./release.sh <version> [notes]"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit your changes first (working tree is dirty)"; exit 1; }
git rev-parse "v$VER" >/dev/null 2>&1 && { echo "tag v$VER already exists"; exit 1; }

BUILD=$(( $(cat build-number 2>/dev/null || echo 0) + 1 ))
echo "$BUILD" > build-number
./build.sh --dist --version "$VER" --build "$BUILD"

python3 - "$VER" "$BUILD" "$RELEASES_REPO" "$NOTES" > build/latest.json <<'PY'
import json, sys
v, b, repo, notes = sys.argv[1:5]
print(json.dumps({"version": v, "build": int(b), "url": f"https://github.com/{repo}/releases/download/v{v}/mdv.zip", "notes": notes}, indent=2))
PY

git add build-number
git commit -q -m "Release $VER (build $BUILD)"
git tag "v$VER"
git push -q origin HEAD
git push -q origin "v$VER"
gh release create "v$VER" build/mdv.zip build/latest.json -R "$RELEASES_REPO" --title "mdv $VER" --notes "$NOTES"
echo "released v$VER → https://github.com/$RELEASES_REPO/releases/tag/v$VER"
