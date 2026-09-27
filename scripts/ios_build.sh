#!/usr/bin/env bash
# SOH-174 — build the Capacitor iOS shell with the backend URL baked in.
#   scripts/ios_build.sh [https://<backend>]   (default: URL in .claude/worktrees/host/.jac/tunnel.log)
# Builds in a source-only mirror ($CIRQL_IOS_DIR, default ~/.cache/cirql-ios), NOT the repo:
# jac build always empties .jac/client/dist, which is what a running `jac start` in the repo serves.
# Then: open Xcode with  (cd ~/.cache/cirql-ios && npx cap open ios)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
URL="${1:-$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$REPO/.claude/worktrees/host/.jac/tunnel.log" | tail -1)}"
[[ "$URL" == https://* ]] || { echo "usage: $0 https://<backend> (HTTPS required for the mic)"; exit 2; }
OUT="${CIRQL_IOS_DIR:-$HOME/.cache/cirql-ios}"
JAC="$REPO/.venv/bin/jac"; [ -x "$JAC" ] || JAC="$(command -v jac)"   # worktrees have no .venv: use jac on PATH
MIC="Cirql records a voice debrief only while you hold the mic button, and sends it to your own account for transcription."
mkdir -p "$OUT"
rsync -a --delete --exclude .git/ --exclude .jac/ --exclude .venv/ --exclude .claude/ --exclude node_modules/ \
  --exclude ios/ --exclude android/ --exclude .env --exclude seed/seed.real.json --exclude .DS_Store "$REPO/" "$OUT/"
cd "$OUT"
npm install --no-audit --no-fund --loglevel=error
"$JAC" install < /dev/null   # jac.toml [dependencies.npm] -> .jac/client (e.g. d3 for the graph view)
[ -d ios ] || "$JAC" setup mobile --platform ios < /dev/null
plist() { /usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription $MIC" ios/App/App/Info.plist 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string $MIC" ios/App/App/Info.plist; }
plist
# SOH-226: app icon + launch splash (ios/ is gitignored and regenerated, so re-apply every build).
XC=ios/App/App/Assets.xcassets
cp assets/icon/icon-1024.png "$XC/AppIcon.appiconset/AppIcon-512@2x.png"
for f in "$XC"/Splash.imageset/splash-2732x2732*.png; do cp assets/icon/splash-2732.png "$f"; done
echo "OK: icon + splash copied into $OUT/$XC"
# Capacitor 8 = SPM, no .xcworkspace; jac-client 0.3.25 passes App.xcodeproj to `xcodebuild -workspace` and fails.
mkdir -p ios/App/App.xcworkspace && printf '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="group:App.xcodeproj"></FileRef></Workspace>\n' > ios/App/App.xcworkspace/contents.xcworkspacedata
# Pre-fetch SPM artifacts anonymously: the keychain provider hangs on a hidden "allow keychain access" prompt for github.com.
(cd ios/App && xcodebuild -resolvePackageDependencies -workspace App.xcworkspace -scheme App -packageAuthorizationProvider netrc -quiet)
JAC_CLIENT_API_BASE_URL="$URL" "$JAC" build main.jac --client mobile --platform ios < /dev/null   # web bundle -> npx cap sync ios -> xcodebuild
plist
grep -lq "$URL" .jac/client/dist/client.*.js && echo "OK: $URL baked into $OUT/.jac/client/dist" || { echo "FAIL: $URL not in bundle"; exit 1; }
APP="$(xcodebuild -workspace ios/App/App.xcworkspace -scheme App -configuration Debug -sdk iphonesimulator -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / WRAPPER_NAME /{w=$2} END{print d"/"w}')"
echo "APP=$APP"
