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
