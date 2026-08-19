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
# One App Store Connect API key does the whole job: -allowProvisioningUpdates
# with the key lets xcodebuild create the distribution certificate and the
# provisioning profile itself, so nothing has to be clicked through Xcode and
# nothing is checked into the repository. The same key authenticates the upload.
#
# Build numbers must rise with every upload — App Store Connect rejects a repeat
# even if the marketing version changed — so the default is a UTC timestamp,
# which is monotonic without needing state anywhere.

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH (the .p8 file)}"

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
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive

step "Exporting"
rm -rf "$OUT/export"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist Tools/ExportOptions.plist \
  -exportPath "$OUT/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

IPA=$(find "$OUT/export" -name '*.ipa' | head -1)
[[ -n "$IPA" ]] || { echo "no .ipa produced" >&2; exit 1; }
printf '    %s (%s)\n' "$IPA" "$(du -h "$IPA" | cut -f1)"

step "Validating"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

if [[ "$DRY_RUN" == 1 ]]; then
  step "Dry run — validated but not uploaded"
  exit 0
fi

step "Uploading"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

step "Uploaded build $BUILD"
echo "    It appears in App Store Connect after processing, usually 5-15 minutes."
echo "    Submitting for review is a Console step: the listing text, age rating"
echo "    and App Privacy answers are not exposed by this API."
