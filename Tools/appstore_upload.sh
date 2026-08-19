#!/usr/bin/env bash
#
# Archive, export and upload to App Store Connect.
#
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   export ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8
#   ./Tools/appstore_upload.sh            # archive, export, upload
#   ./Tools/appstore_upload.sh --dry-run  # archive and export only
#
# The archive is built unsigned and signed during export, which is deliberate.
# `xcodebuild archive` with automatic signing asks for a *development* profile,
# and a development profile requires at least one registered device — so on a
# machine with no iPhone attached it fails with "your team has no devices". App
# Store distribution profiles have no device list at all, so doing the signing at
# export sidesteps the whole problem. The team has to be named in
# ExportOptions.plist, because an unsigned archive records none.
#
# Build numbers must rise with every upload — App Store Connect rejects a repeat
# even if the marketing version changed — so the default is a UTC timestamp,
# which is monotonic without needing state anywhere.

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# Signing uses the Apple ID signed into Xcode. Only the upload needs a separate
# credential: either an App Store Connect API key, or an app-specific password.
if [[ "$DRY_RUN" == 0 ]]; then
  if [[ -n "${ASC_KEY_ID:-}" ]]; then
    : "${ASC_ISSUER_ID:?ASC_KEY_ID is set, so ASC_ISSUER_ID is needed too}"
    AUTH=(--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID")
  elif [[ -n "${APP_PASSWORD:-}" ]]; then
    : "${APPLE_ID:?set APPLE_ID alongside APP_PASSWORD}"
    AUTH=(--username "$APPLE_ID" --password "@env:APP_PASSWORD")
  else
    echo "set either ASC_KEY_ID + ASC_ISSUER_ID, or APPLE_ID + APP_PASSWORD" >&2
    exit 2
  fi
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

BUILD="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
OUT="${OUT_DIR:-build}"
ARCHIVE="$OUT/WeeklyBudget.xcarchive"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "Core suite first"
# The sync engine is the part that can lose someone's data; it should never be
# shipped on a red suite, and it costs a couple of seconds.
( cd Core && swift run BudgetCoreTests )

step "Archiving (build $BUILD)"
rm -rf "$ARCHIVE"
xcodebuild -scheme WeeklyBudget -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive

step "Exporting"
rm -rf "$OUT/export"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist Tools/ExportOptions.plist \
  -exportPath "$OUT/export" \
  -allowProvisioningUpdates

IPA=$(find "$OUT/export" -name '*.ipa' | head -1)
[[ -n "$IPA" ]] || { echo "no .ipa produced" >&2; exit 1; }
printf '    %s (%s)\n' "$IPA" "$(du -h "$IPA" | cut -f1)"

step "Validating"
if [[ "$DRY_RUN" == 1 ]]; then
  step "Dry run — built and exported, not validated or uploaded"
  exit 0
fi
xcrun altool --validate-app -f "$IPA" -t ios "${AUTH[@]}"

step "Uploading"
xcrun altool --upload-app -f "$IPA" -t ios "${AUTH[@]}"

step "Uploaded build $BUILD"
echo "    It appears in App Store Connect after processing, usually 5-15 minutes."
echo "    Submitting for review is a Console step: the listing text, age rating"
echo "    and App Privacy answers are not exposed by this API."
