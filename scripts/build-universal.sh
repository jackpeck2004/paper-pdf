#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for arch in arm64 x86_64; do
  PAPER_ARCH="$arch" bash scripts/bootstrap.sh
  PAPER_ARCH="$arch" PAPER_BUILD_DIR=".build/native-$arch" bash scripts/build-native.sh
done
mkdir -p .build/native
lipo -create .build/native-arm64/Paper .build/native-x86_64/Paper -output .build/native/Paper
PAPER_SKIP_BUILD=1 bash scripts/build-app.sh
lipo -info build/Paper.app/Contents/MacOS/Paper
