#!/usr/bin/env bash
# notarize.sh — Export, package, notarize, and staple Teloscope.app
# Called by Xcode Archive Post-action with $ARCHIVE_PATH as $1.
#
# One-time setup:
#   1. Install "Developer ID Application" certificate via Xcode > Settings > Accounts
#   2. xcrun notarytool store-credentials "TeloscopeNotarize" \
#        --apple-id "you@example.com" \
#        --team-id "XXXXXXXXXX" \
#        --password "xxxx-xxxx-xxxx-xxxx"   # app-specific password from appleid.apple.com
#   3. Edit scripts/ExportOptions.plist: replace XXXXXXXXXX with your Team ID

set -euo pipefail

# ── Error handler ─────────────────────────────────────────────────────────────
_on_error() {
    local exit_code=$?
    local line=$1
    # Write to stderr so Xcode build log captures it (before exec redirect)
    echo "ERROR: notarize.sh failed at line ${line} (exit ${exit_code})" >&2
    # Show a dialog — osascript uses its own stderr, unaffected by exec redirect
    osascript -e "display alert \"Notarization Failed\" message \"notarize.sh failed at line ${line} (exit ${exit_code}).\\n\\nSee: ${LOG_FILE:-notarize.log}\" as critical" >/dev/null 2>&1 || true
}
trap '_on_error $LINENO' ERR

# ── Configuration ─────────────────────────────────────────────────────────────
KEYCHAIN_PROFILE="TeloscopeNotarize"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_OPTIONS_PLIST="${SCRIPT_DIR}/ExportOptions.plist"
OUTPUT_DIR="${HOME}/Documents/Teloscope/${MARKETING_VERSION}"
LOG_FILE="${OUTPUT_DIR}/notarize.log"

# ── Resolve archive path ───────────────────────────────────────────────────────
ARCHIVE_PATH="${1:-}"
if [[ -z "${ARCHIVE_PATH}" ]]; then
    echo "ERROR: ARCHIVE_PATH not provided as argument" >&2
    exit 1
fi

# ── Prepare output directory ───────────────────────────────────────────────────
mkdir -p "${OUTPUT_DIR}"

# ── Redirect all output to log file from here (append) ────────────────────────
exec >> "${LOG_FILE}" 2>&1

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Teloscope Notarization — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Archive : ${ARCHIVE_PATH}"
echo "  Version : ${MARKETING_VERSION} (${CURRENT_PROJECT_VERSION})"
echo "════════════════════════════════════════════════════════════"

# ── Step 1: Export .app from .xcarchive ───────────────────────────────────────
EXPORT_DIR="${TMPDIR}teloscope-export-$$"
mkdir -p "${EXPORT_DIR}"

echo "[1/5] Exporting .app from archive..."
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
    -allowProvisioningUpdates

APP_PATH="${EXPORT_DIR}/Teloscope.app"
if [[ ! -d "${APP_PATH}" ]]; then
    echo "ERROR: Export succeeded but Teloscope.app not found at ${APP_PATH}"
    exit 1
fi
echo "  Exported to: ${APP_PATH}"

# ── Step 2: Create DMG ────────────────────────────────────────────────────────
DMG_NAME="Teloscope-${MARKETING_VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
STAGING_DIR="${TMPDIR}teloscope-dmg-staging-$$"
VOL_NAME="Teloscope ${MARKETING_VERSION}"

echo "[2/5] Creating DMG: ${DMG_NAME}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

[[ -f "${DMG_PATH}" ]] && rm -f "${DMG_PATH}"

# Detach any leftover volume with the same name from a previous failed run
if [[ -d "/Volumes/${VOL_NAME}" ]]; then
    hdiutil detach "/Volumes/${VOL_NAME}" -quiet -force || true
fi

hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_PATH}"

echo "  DMG created at: ${DMG_PATH}"

# ── Step 3: Submit for notarization ───────────────────────────────────────────
echo "[3/5] Submitting to Apple notarization service (this may take several minutes)..."
NOTARIZE_OUTPUT="$(xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait \
    2>&1)"
echo "${NOTARIZE_OUTPUT}"

SUBMISSION_ID="$(echo "${NOTARIZE_OUTPUT}" | grep -E '^\s+id:' | head -1 | awk '{print $2}')"
echo "  Submission ID: ${SUBMISSION_ID:-unknown}"

if ! echo "${NOTARIZE_OUTPUT}" | grep -q "status: Accepted"; then
    echo "ERROR: Notarization was not accepted. Fetching notarization log..."
    if [[ -n "${SUBMISSION_ID}" ]]; then
        xcrun notarytool log "${SUBMISSION_ID}" \
            --keychain-profile "${KEYCHAIN_PROFILE}" || true
    fi
    rm -rf "${EXPORT_DIR}" "${STAGING_DIR}"
    exit 1
fi
echo "  Notarization accepted."

# ── Step 4: Staple ticket to DMG ───────────────────────────────────────────────
echo "[4/5] Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}"
echo "  Staple complete."

# ── Step 5: Verify staple ─────────────────────────────────────────────────────
echo "[5/5] Verifying stapled DMG..."
xcrun stapler validate "${DMG_PATH}"

# ── Step 6: Archive dSYMs ─────────────────────────────────────────────────────
DSYM_ZIP="${OUTPUT_DIR}/Teloscope-${MARKETING_VERSION}-dSYM.zip"
DSYM_DIR="${ARCHIVE_PATH}/dSYMs"

echo "[6/6] Archiving dSYMs: Teloscope-${MARKETING_VERSION}.zip"
[[ -f "${DSYM_ZIP}" ]] && rm -f "${DSYM_ZIP}"
ditto -c -k --keepParent "${DSYM_DIR}" "${DSYM_ZIP}"
echo "  dSYM zip created at: ${DSYM_ZIP}"

# ── Cleanup ────────────────────────────────────────────────────────────────────
rm -rf "${EXPORT_DIR}" "${STAGING_DIR}"

echo ""
echo "SUCCESS"
echo "  DMG : ${DMG_PATH}"
echo "  dSYM: ${DSYM_ZIP}"
echo "  Log : ${LOG_FILE}"
echo "════════════════════════════════════════════════════════════"

open "${OUTPUT_DIR}"
