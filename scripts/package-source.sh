#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
if [ -e Vendor/mupdf/.git ]; then
  git -C Vendor/mupdf submodule status --recursive > Vendor/DEPENDENCY_REVISIONS.txt
fi
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
# Include the complete corresponding engine source and dependencies, without caches.
tar --exclude='.git' --exclude='build' --exclude='.build' --exclude='.DS_Store' -czf "build/Paper-$version-source.tar.gz" Package.swift .gitmodules Casks Sources Tests Resources scripts docs Samples licenses LICENSE THIRD_PARTY_NOTICES.md README.md Vendor
shasum -a 256 "build/Paper-$version-source.tar.gz"
