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
CAMERA="Cirql uses the camera to read a badge or business card into a person."
PHOTO="Cirql reads a photo you choose to add the person on it."
# SOH-226: App Store readiness. jac_client's built-in Info.plist has $(MARKETING_VERSION) /
# $(CURRENT_PROJECT_VERSION) macros baked in by `jac setup mobile` (pbxproj default 1.0 / 1);
# pass real values as xcodebuild settings on our own rebuild below instead of editing the pbxproj.
MARKETING_VERSION="0.1.0"
CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H)"
mkdir -p "$OUT"
rsync -a --delete --exclude .git/ --exclude .jac/ --exclude .venv/ --exclude .claude/ --exclude node_modules/ \
  --exclude ios/ --exclude android/ --exclude .env --exclude seed/seed.real.json --exclude .DS_Store "$REPO/" "$OUT/"
cd "$OUT"
npm install --no-audit --no-fund --loglevel=error
"$JAC" install < /dev/null   # jac.toml [dependencies.npm] -> .jac/client (e.g. d3 for the graph view)
[ -d ios ] || "$JAC" setup mobile --platform ios < /dev/null
PLIST=ios/App/App/Info.plist
plist() {
  /usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription $MIC" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string $MIC" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :NSCameraUsageDescription $CAMERA" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string $CAMERA" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :NSPhotoLibraryUsageDescription $PHOTO" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryUsageDescription string $PHOTO" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Cirql" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Cirql" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :ITSAppUsesNonExemptEncryption false" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$PLIST"
  # Only add if absent: never override an existing value, and never touch UIStatusBarStyle.
  /usr/libexec/PlistBuddy -c "Print :UIViewControllerBasedStatusBarAppearance" "$PLIST" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add :UIViewControllerBasedStatusBarAppearance bool true" "$PLIST"
}
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
# jac_client's own xcodebuild call (bundle.jac _build_ios) takes no passthrough args, so re-run the
# same workspace/scheme/configuration/destination ourselves with the two version settings overridden;
# nothing else changed source-side, so this is an incremental relink, not a full rebuild.
(cd ios/App && xcodebuild -workspace App.xcworkspace -scheme App -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" build \
  MARKETING_VERSION="$MARKETING_VERSION" CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" -quiet)
plist
grep -lq "$URL" .jac/client/dist/client.*.js && echo "OK: $URL baked into $OUT/.jac/client/dist" || { echo "FAIL: $URL not in bundle"; exit 1; }
APP="$(xcodebuild -workspace ios/App/App.xcworkspace -scheme App -configuration Debug -sdk iphonesimulator -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / WRAPPER_NAME /{w=$2} END{print d"/"w}')"
echo "APP=$APP"
