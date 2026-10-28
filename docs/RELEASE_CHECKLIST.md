# Release verification

Automated checks: `bash scripts/test-native.sh` (or `swift test` with a working Xcode installation), `codesign --verify --strict --deep build/Paper.app`, and `lipo -info build/Paper.app/Contents/MacOS/Paper`.

Manual release gates:

- Open born-digital, scanned, encrypted, malformed, mixed-font, subset-font, Unicode, rotated, cropped, tagged, signed, and large PDFs. Verify clear failures and bounded memory use.
- Add each markup type; edit/delete notes; save, close, reopen in Paper, Preview, and Acrobat Reader. Verify editable annotations and line placement at different zoom/rotation values.
- Correct text over colored/image backgrounds. Confirm old wording cannot be searched or recovered from the exported content streams, while unrelated content remains unchanged.
- Move/resize/replace/delete supported images, including shared resources on multiple pages. Verify other occurrences are unchanged. Verify clipping, masks, and unsupported geometry fail atomically.
- Fill text, checkbox, radio, and choice fields. Verify appearance/state in Preview and Acrobat Reader. Check read-only fields and documents reject mutation; scripts and XFA never execute.
- Merge/extract/reorder/delete/duplicate pages with comments and links. Verify outlines and destination pages. Verify form-containing imports reject with the original document unchanged.
- Draw/import/reuse visual signatures; inspect local file permissions. Verify no certificate-signing claim is made.
- OCR scan pages; verify selectable text, visual fidelity, Unicode, cancellation/stale revisions, and that text-bearing pages are skipped.
- Redact text, images, vectors, and content crossing selection edges. Independently inspect exported objects and history; do not rely on appearance alone.
- Exercise undo/redo across mixed operations and Save As. Save and reopen encrypted outputs, flattened PDFs, downsampled PDFs, PNGs, and annotation summaries.
- Interrupt a save and terminate with unsaved changes; confirm NSDocument recovery. Trigger OCR while editing/saving and confirm stale output rejection.
- Inspect default/minimum window sizes, sidebar/inspector toggles, full screen, tabs, toolbar customization, dark mode, keyboard-only use, and VoiceOver.
- Run on Apple Silicon and Intel, macOS 14 and a current macOS release. Verify system-framework availability and universal binary dependencies.
- Check complete dependency notices and corresponding source archive; build the unpacked source offline after dependencies are included.
- Sign with Developer ID and hardened runtime, notarize, staple, then verify Gatekeeper on a different Mac.

Do not describe unfinished manual gates as validated release behavior.
