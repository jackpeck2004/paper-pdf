#!/bin/bash
# Direct compiler build also works when the host's SwiftPM installation is broken.
set -euo pipefail
cd "$(dirname "$0")/.."
arch=${PAPER_ARCH:-$(uname -m)}
out=${PAPER_BUILD_DIR:-.build/native}
mkdir -p "$out"
sdk=${PAPER_SDK:-$(xcrun --show-sdk-path)}
flags=(-sdk "$sdk" -module-cache-path "$PWD/.build/ModuleCache" -target "$arch-apple-macosx14.0")
clang -isysroot "$sdk" -target "$arch-apple-macosx14.0" -O2 -I Vendor/mupdf/include -I Sources/CPDFEngine/include -c Sources/CPDFEngine/Engine.c -o "$out/Engine.o"
ar rcs "$out/libCPDFEngine.a" "$out/Engine.o"
swiftc "${flags[@]}" -swift-version 5 -O -emit-library -static -emit-module -module-name PaperCore -I Sources/CPDFEngine/include Sources/PaperCore/*.swift -o "$out/libPaperCore.a" -emit-module-path "$out/PaperCore.swiftmodule"
if [ "${PAPER_CORE_ONLY:-0}" = 1 ]; then exit 0; fi
swiftc "${flags[@]}" -swift-version 5 -O -I "$out" -I Sources/CPDFEngine/include -L "$out" -L "Vendor/mupdf/build/$arch-release" Sources/Paper/*.swift -lPaperCore -lCPDFEngine -lmupdf -lmupdf-third -lc++ -lz -framework AppKit -framework PDFKit -framework Vision -framework CoreFoundation -o "$out/Paper"
