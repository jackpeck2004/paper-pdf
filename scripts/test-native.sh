#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/native
PAPER_CORE_ONLY=1 PAPER_BUILD_DIR=.build/tests bash scripts/build-native.sh
sdk=${PAPER_SDK:-$(xcrun --show-sdk-path)}
app_sources=()
for path in Sources/Paper/*.swift; do
  if [ "$path" != Sources/Paper/main.swift ]; then app_sources+=("$path"); fi
done
swiftc -sdk "$sdk" -module-cache-path "$PWD/.build/ModuleCache" -target "$(uname -m)-apple-macosx14.0" -swift-version 5 -D PAPER_NATIVE_TESTS -g -I .build/tests -I Sources/CPDFEngine/include -L .build/tests -L "Vendor/mupdf/build/$(uname -m)-release" "${app_sources[@]}" Tests/PaperCoreTests/*.swift Tests/NativeRunner/*.swift -lPaperCore -lCPDFEngine -lmupdf -lmupdf-third -lc++ -lz -framework AppKit -framework PDFKit -framework Vision -o .build/native/PaperTests
.build/native/PaperTests
