# Validation record — 27 October 2026

- Built the native app using Swift 6.3.3, the compatible installed macOS 26.5 SDK, and a macOS 14 deployment target.
- Built MuPDF 1.28.5 and its linked dependencies independently for arm64 and x86_64 with a macOS 14 deployment target.
- Created a universal app; `lipo` reports `x86_64 arm64` and both Mach-O slices report a minimum OS version of 14.0.
- Verified the local ad-hoc code signature with `codesign --verify --deep --strict`.
- Launched the app and inspected its native document window and accessibility tree.
- Passed all 18 generated-fixture regression/native integration checks. This includes real Apple Vision OCR, actual source-text removal and background retention, image removal, catalog/form preservation, independent duplicates/internal links, native controller markup, undo/redo, atomic saves, and reopening.
- The sandboxed Vision run could not allocate a pixel buffer; the ordinary unrestricted local run passed. No network OCR service was used.
- Standard SwiftPM is broken on this machine due to an incompatible BuildServerProtocol framework. The direct compiler build and test scripts were used successfully. No system settings were changed.

Not verified: execution on Intel hardware or macOS 14, broad real-world PDF compatibility, full keyboard/VoiceOver workflows, crash-interruption recovery, independent Acrobat Reader interoperability, notarization, and production security certification. See RELEASE_CHECKLIST.md. No valid Developer ID signing identity was present.

## UI, book navigation, and reader controls — 28 October 2026

- Replaced the tool dropdown with a system icon toolbar group and a floating markup palette. Added native macOS 26 `NSGlassEffectView` surfaces with native material fallbacks on older macOS versions.
- Added resizable split-view sidebars and an actual collapsible chapter tree. Embedded outlines remain authoritative; printed TOCs/headings are inferred only in their absence. Regression cases cover front-matter offsets, subsection hierarchy, repeated headers, plain lists, and absent text.
- Replaced text-correction/annotation/form text alerts with on-page editors. Added structured image-position inspector controls. Tests verify commit, cancellation, and undo.
- Added a visible View menu, page field, all four layouts, Go menu, page navigation, and shortcut aliases. Verified menu key-equivalent dispatch, checked layout selection, and responder-chain delivery from the PDF canvas. Avoided the PDFView `goToPage:` selector collision by using a distinct command selector.
- All 27 engine, chapter extraction, native controller, layout, reader-command, and OCR checks passed in an ordinary local process with the installed macOS 26.5 SDK. The new layout is checked at 1120×800 and 820×560.
- Live visual inspection could not complete: the macOS ScreenCaptureKit service failed to start its capture stream. Offscreen view renders omit compositor-managed glass/layer content and are not proof of final visual appearance. Full visual acceptance remains a manual check.

## License and app icon — 28 October 2026

- At the user's explicit selection, changed Paper-authored source to MIT while retaining MuPDF's AGPL terms and combined-distribution requirements. Preserved the AGPL text, all vendor notices, and the complete corresponding source packaging.
- Created an app icon with built-in ImageGen; generated and packaged standard macOS icon representations. Apple's `iconutil` required an ordinary local process on this machine; the sandboxed run rejected an otherwise valid iconset. Icon generation succeeds outside that sandbox.
- About now uses the standard macOS About panel. The bundle declares its icon and includes the MIT and MuPDF notices.

## Preview-style sidebar and public distribution — 28 October 2026

- Replaced custom page rows with Apple's `PDFThumbnailView`: one column of large page previews, system selection styling, page labels underneath, and native multi-selection/drag gestures.
- Removed the segmented sidebar header in favor of the toolbar's sidebar disclosure menu. Removed the duplicate toolbar page capsule; Go to Page focuses the single footer control.
- Native page-drag notifications are deferred through the app run loop and translated into serialized MuPDF commands. A regression test posts the native notification and verifies persistence and undo.
- All 29 engine and native regression checks passed. The release remains ad-hoc signed; notarization and live visual acceptance remain separate release gates.

## Outline column sizing — 28 October 2026

- Replaced the constrained title/page stack with native, separate outline columns: a flexible chapter-title column and a fixed trailing page-number column.
- Made the title column track the scroll viewport during sidebar resizing, left-aligned the outline caption, and supplied full-title tooltips.
- All 30 regression checks pass, including explicit column-sizing checks at narrow and wide sidebar widths.

## Document lifetime crash — 28 October 2026

- Reproduced the supplied 0.2.1 crash on the 0.2.2 source: a retained viewer receiving PDFKit scale/page notifications after its document was destroyed aborted on an unowned reference.
- Replaced the document reference with weak ownership. Document-dependent actions acquire a local strong reference or return; delayed inline-editor and background callbacks tolerate a missing document.
- Added a native regression that releases the document while retaining its viewer, posts scale/page notifications, resizes the PDF canvas, invokes page actions, and commits an existing inline text editor. The weak-document assertion also checks that the fix does not retain the document.
- All 31 native regression checks passed, including on-device OCR, with the compatible macOS 26.5 SDK.

## Visible text boxes — 28 October 2026

- Reproduced the solid-rectangle bug with a colored FreeText annotation: the same RGB color was written into the box fill (`/C`) and text appearance (`/DA`). Pixel checks failed on editable and flattened exports before the fix.
- FreeText now has transparent fill and no border; the chosen color applies to glyphs. Other annotation styles are unchanged. Text defaults to black rather than a color that changes with the system's light/dark appearance.
- Text Box supports clicking to type or dragging a width. The saved area expands for multiline content within the page, and empty input adds no annotation.
- All 33 native checks pass. New coverage verifies visible glyph pixels, preserved background, editable and flattened export, real mouse click dispatch, multiline sizing, reediting, saving/reopening, empty-input cancellation, and undo/redo.
