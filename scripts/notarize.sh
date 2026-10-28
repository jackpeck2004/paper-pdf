#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CODE_SIGN_IDENTITY:?Set a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set the name of an existing notarytool keychain profile}"
app="$PWD/build/Paper.app"
codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$app"
codesign --verify --strict --deep "$app"
ditto -c -k --keepParent "$app" build/Paper-notarize.zip
xcrun notarytool submit build/Paper-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"
