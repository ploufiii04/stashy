#!/bin/bash
# SPM (KSPlayer → FFmpegKit) liefert Frameworks mit CFBundleIdentifier mit Unterstrichen;
# Xcode/Validation akzeptiert das nicht (nur A–Z, a–z, 0–9, Punkt, Bindestrich).
# Ersetzt '_' durch '-' und signiert das Framework neu, falls eine Identität gesetzt ist.

set -uo pipefail

APP_ROOT=""
if [ -n "${CODESIGNING_FOLDER_PATH:-}" ] && [ -d "${CODESIGNING_FOLDER_PATH}" ]; then
  APP_ROOT="$CODESIGNING_FOLDER_PATH"
elif [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${WRAPPER_NAME:-}" ]; then
  APP_ROOT="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
fi

if [ -z "$APP_ROOT" ] || [ ! -d "$APP_ROOT" ]; then
  exit 0
fi

FWK_DIR="${APP_ROOT}/Frameworks"
if [ ! -d "$FWK_DIR" ]; then
  exit 0
fi

shopt -s nullglob
for fw in "$FWK_DIR"/*.framework; do
  plist="${fw}/Info.plist"
  [ -f "$plist" ] || continue
  id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)
  [ -n "$id" ] || continue
  [[ "$id" == *"_"* ]] || continue

  new="${id//_/-}"
  echo "note: patch_embedded_framework_bundle_ids: $(basename "$fw") CFBundleIdentifier: ${id} -> ${new}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${new}" "$plist"

  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "$fw"
  fi
done
