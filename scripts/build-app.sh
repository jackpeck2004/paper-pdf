#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${PAPER_SKIP_BUILD:-0}" != 1 ]; then bash scripts/build-native.sh; fi
bin="$PWD/.build/native"
destination=${PAPER_APP_PATH:-"$PWD/build/Paper.app"}
staging=$(mktemp -d "$PWD/.build/app-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Paper.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses"
cp "$bin/Paper" "$app/Contents/MacOS/Paper"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ] || [ Resources/AppIcon.png -nt Resources/AppIcon.icns ] || [ scripts/build-icon.sh -nt Resources/AppIcon.icns ]; then bash scripts/build-icon.sh; fi
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp LICENSE "$app/Contents/Resources/Licenses/Paper-MIT.txt"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/Licenses/"
cp Vendor/mupdf/COPYING "$app/Contents/Resources/Licenses/MuPDF-AGPL-3.0.txt"
python3 - "$app/Contents/Resources/Licenses/MuPDF" <<'PYLICENSE'
import pathlib, shutil, sys
root = pathlib.Path('Vendor/mupdf')
for path in root.rglob('*'):
    if path.is_file() and path.name.lower().startswith(('copying','license','notice')) and 'build' not in path.relative_to(root).parts and '.git' not in path.relative_to(root).parts:
        destination = pathlib.Path(sys.argv[1]) / path.relative_to(root)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path,destination)
PYLICENSE
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$app"
# Replace the complete bundle without truncating a running app's executable.
mkdir -p "$(dirname "$destination")"
if [ -d "$destination" ]; then mv "$destination" "$staging/Previous.app"; fi
if ! mv "$app" "$destination"; then
  if [ -d "$staging/Previous.app" ]; then mv "$staging/Previous.app" "$destination"; fi
  exit 1
fi
echo "$destination"
