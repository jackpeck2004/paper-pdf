#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
revision=8ad45e92f0935d3d87f1db3f873086472a5e1b24
if [ ! -f Vendor/mupdf/include/mupdf/fitz.h ]; then
  if [ -f .gitmodules ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git submodule update --init --recursive --depth 1 Vendor/mupdf
  else
    git clone --depth 1 --branch 1.28.5 --recurse-submodules --shallow-submodules https://github.com/ArtifexSoftware/mupdf.git Vendor/mupdf
  fi
fi
if [ -e Vendor/mupdf/.git ]; then
  test "$(git -C Vendor/mupdf rev-parse HEAD)" = "$revision"
  printf '%s\n' "$revision" > Vendor/mupdf/.paper-revision
else
  test "$(cat Vendor/mupdf/.paper-revision)" = "$revision"
fi
sdk=${PAPER_SDK:-$(xcrun --show-sdk-path)}
arch=${PAPER_ARCH:-$(uname -m)}
jobs=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
make -C Vendor/mupdf -j"$jobs" build=release OUT="build/$arch-release" XCFLAGS="-target $arch-apple-macosx14.0 -isysroot $sdk" HAVE_GLUT=no HAVE_X11=no HAVE_CURL=no HAVE_LIBCRYPTO=no USE_TESSERACT=no USE_LEPTONICA=no USE_ZXINGCPP=no USE_ZINT=no libs
