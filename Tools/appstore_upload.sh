#!/usr/bin/env bash
#
# Archive, export and upload to App Store Connect.
#
#   ./Tools/appstore_upload.sh            # archive, sign, upload
#   ./Tools/appstore_upload.sh --dry-run  # archive and sign, write an .ipa
#
# Needs only the Apple ID signed into Xcode. No API key, no app-specific
# password, no keychain juggling.
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

# No separate upload credential is needed. `xcodebuild -exportArchive` with
# destination=upload authenticates with the Apple ID already signed into Xcode
# and uploads as part of the export, so there is no altool step and no
# app-specific password or API key to manage. That also means one authenticated
# tool does the whole job instead of two.

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

# destination=export writes an .ipa; destination=upload sends it. Dry runs take
# the first path so a build can be inspected without shipping it.
OPTIONS=Tools/ExportOptions.plist
if [[ "$DRY_RUN" == 0 ]]; then
  OPTIONS=$(mktemp -t ExportOptions).plist
  cp Tools/ExportOptions.plist "$OPTIONS"
  /usr/libexec/PlistBuddy -c "Set :destination upload" "$OPTIONS"
fi

step "$([[ "$DRY_RUN" == 1 ]] && echo Exporting || echo 'Exporting and uploading')"
rm -rf "$OUT/export"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$OUT/export" \
  -allowProvisioningUpdates

if [[ "$DRY_RUN" == 1 ]]; then
  IPA=$(find "$OUT/export" -name '*.ipa' | head -1)
  step "Dry run — exported, not uploaded"
  printf '    %s (%s)\n' "$IPA" "$(du -h "$IPA" | cut -f1)"
  exit 0
fi

step "Uploaded build $BUILD"
echo "    It appears in App Store Connect after processing, usually 5-15 minutes."
echo "    Submitting for review is a Console step: the listing text, age rating"
echo "    and App Privacy answers are not exposed by this API."
