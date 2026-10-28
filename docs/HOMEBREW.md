# Homebrew distribution

Install the universal macOS app from the project's public tap:

```sh
brew install --cask jackpeck2004/paper/paper-pdf
```

Or explicitly tap first:

```sh
brew tap jackpeck2004/paper
brew install --cask paper-pdf
```

The tap is https://github.com/jackpeck2004/homebrew-paper. The canonical cask is also kept in this app repository under `Casks/paper-pdf.rb`.

The cask installs `Paper.app` from the immutable, versioned GitHub release URL and verifies its SHA-256. It requires macOS 14 Sonoma or later and contains Apple Silicon and Intel binaries. It does not build MuPDF on the end user's machine. Standard uninstall removes the app; the cask deliberately does not delete saved signatures, preferences, or recovery documents.

The current binary is ad-hoc signed, not Developer ID signed or notarized. macOS may require the user to approve its first launch through Privacy & Security. No cask hooks remove quarantine or bypass Gatekeeper. Developer ID/notarization remains a release gate, documented in RELEASE_CHECKLIST.md.

## Updating a release

1. Update the application version in `Resources/Info.plist` and About metadata.
2. Build and test with a matching Xcode 26+ toolchain:

   ```sh
   bash scripts/build-universal.sh
   bash scripts/test-native.sh
   bash scripts/package-source.sh
   ```

3. ZIP `build/Paper.app` with `ditto -c -k --keepParent`; calculate its SHA-256.
4. Update the cask's version and checksum in both this repository and the public tap. Commit the source and tag the release `vVERSION`.
5. Publish the versioned universal app ZIP, complete corresponding source archive (including MuPDF and its dependencies), and `SHA256SUMS` as GitHub release assets. Preserve Paper's MIT notices and all MuPDF AGPL distribution requirements.
6. Run `brew style --cask Casks/paper-pdf.rb`, fetch the published cask with Homebrew, and verify an installation from the actual public release download. Never replace published binary bytes without updating the release version and checksum.
