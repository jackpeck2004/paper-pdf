# Paper

A free, open-source native PDF editor for macOS 14 and later, written in Swift/AppKit with Apple PDFKit and a statically linked MuPDF engine. Paper’s original source code is licensed under MIT. The bundled MuPDF engine remains AGPL v3 or later, and distribution of this combined build must satisfy its AGPL requirements. No accounts, subscriptions, telemetry, network services, AI, Electron, or web views.

## Install

```sh
brew install --cask jackpeck2004/paper/paper-pdf
```

Requires macOS 14 Sonoma or later. The download is a universal app for Apple Silicon and Intel. You can also download the app ZIP and complete source bundle from [GitHub Releases](https://github.com/jackpeck2004/paper-pdf/releases).

This development release is ad-hoc signed and not notarized. macOS may ask you to approve its first launch in System Settings → Privacy & Security. The Homebrew cask does not bypass these protections.

See [Homebrew distribution](docs/HOMEBREW.md) for updating and uninstalling the package.

## Run

The local development application is `build/Paper.app`. Double-click it, or run:

```sh
open build/Paper.app
```

This build is ad-hoc signed for local use. Developer ID signing and Apple notarization require your own credentials. Apple Silicon execution is tested on the development machine; the universal binary contains both Apple Silicon and Intel slices. Intel execution and macOS 14 compatibility still need testing on those systems.

## Build from source

Requirements: macOS, Xcode 26+ or matching Command Line Tools with a macOS 26+ SDK, Git, and Make. The deployment target remains macOS 14; the newer SDK is needed to compile the native Liquid Glass APIs. No Homebrew packages or proprietary SDKs are needed.

```sh
git clone --recurse-submodules https://github.com/jackpeck2004/paper-pdf.git
cd paper-pdf
bash scripts/bootstrap.sh
bash scripts/build-app.sh
bash scripts/test-native.sh
```

`bootstrap.sh` initializes the pinned MuPDF 1.28.5 Git submodule and its recursive dependencies and builds it for the host architecture with a macOS 14 deployment target. It makes no system-wide installations. Initial download/build takes several minutes. Subsequent builds reuse engine artifacts.

For a universal app:

```sh
bash scripts/build-universal.sh
```

Both architectures are compiled independently and combined with `lipo`. Apple frameworks remain macOS system dependencies. Every bundled dependency's source and license are retained.

A `Package.swift` is also provided for Xcode and standard SwiftPM installations. Run the bootstrap script before `swift build` or `swift test`. The direct compiler scripts are available because this development machine's SwiftPM executable has an incompatible framework installation.

On this specific development machine, `xcrun` chooses an SDK newer than the installed compiler. Use the compatible installed SDK without changing system configuration:

```sh
export PAPER_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
bash scripts/build-app.sh
bash scripts/test-native.sh
```

The direct test runner executes the same core regression methods as XCTest, plus native NSDocument/controller integration checks, and also works on Command Line Tools installations that do not include XCTest.

## Use

- Open a PDF from Finder or **File → Open**. Each document has its own native window; use the Window menu for tabs.
- Choose an icon in the toolbar. The Markup button (⇧⌘A) reveals the floating icon palette for all tools. On macOS 26+, the palette and floating editing controls use native Liquid Glass; macOS 14–15 use system visual-effect materials. Most placement tools use a drag on the page. Highlight, underline, and strikethrough apply to selected text.
- Choose the **Correct Text** icon, then click a line. Type directly on the page and press Return or Apply; Escape cancels. The floating markup palette provides font, size, and color controls. Original glyphs are removed; the page background stays intact. Text boxes, comments, and text form fields also use on-page editing.
- Choose **Select**, then click an annotation to edit its comment or move/resize supported annotation types in the inspector. Select a link to edit its destination or delete it.
- **Edit Image** selects an existing page image for move, resize, replacement, or deletion through a structured inspector. Placed images and visual signatures are editable stamp annotations and use the Select tool.
- The sidebar menu switches between large native page thumbnails, a collapsible chapter outline, and searchable notes. Thumbnails have page numbers underneath and use the system selection appearance, with no segmented header. Embedded PDF outlines are preferred; when absent, Paper detects chapters from printed contents pages and text headings in the background, matching destinations to account for front matter. Detected chapters are labelled as inferred navigation and do not modify the PDF. Drag page thumbnails to reorder; use Command/Shift to select multiple pages. Drop PDFs/images to insert pages.
- Use the Pages menu for merge, extract, duplicate, delete, rotation, and blank pages. Choose Crop and drag to change the visible page box.
- Choose **Fill Form**, then click a field, or use **Tools → Fill Form Field**. AcroForm text, button, and choice values are supported without running document scripts.
- Choose **Signature**, drag an area, and draw or import a signature. Signatures are stored under `~/Library/Application Support/Paper/Signatures`, with owner-only permissions. They are visual signatures, not certificate signatures.
- **Tools → Recognize Text on Current Page** recognizes selected scan pages entirely on device using Apple Vision. Existing text pages are skipped. OCR creates an invisible searchable text layer; it does not replace scan pixels.
- **File → Export** offers editable PDF, flattened PDF, compressed PDF with optional 150 dpi image downsampling, current-page PNG, or an annotation summary. PDF exports accept an optional password. Compression is lossy where downsampling applies and cannot guarantee a smaller file.
- **Save** preserves editable annotations. Opening an encrypted PDF prompts for its password; saved changes use that password. Exporting without a password produces an unencrypted copy.
- Certificate-signed documents require consent before editing and a new save location. Saving an unchanged signed document preserves its original bytes. Exported rewrites invalidate certificate signatures.

## Keyboard and page layout

The toolbar has an explicit **View** menu for Single Page, Continuous, Two Pages, and Two Pages Continuous, with a checkmark for the current layout. The single page field at the bottom left accepts physical page numbers or matching PDF page labels; there is no duplicate toolbar page counter.

| Action | Shortcut |
| --- | --- |
| Go to page field | ⌥⌘G, ⌘L, or ⇧⌘N |
| Single page | ⌘1 |
| Continuous | ⌘2 |
| Two pages | ⌘3 |
| Two pages continuous | ⌘4 |
| Next / previous page | ⌥⌘↓ / ⌥⌘↑ |
| First / last page | ⌘Home / ⌘End |
| Toggle markup palette | ⇧⌘A |
| Fit page | ⌘0 |

## Design

`PaperCore` owns a serialized MuPDF engine. Commands run on a candidate document and commit only after its complete PDF serialization reopens successfully. Failures leave the current document unchanged. Revision numbers reject stale OCR results. PDFKit is a snapshot viewer and never independently saves the authoritative document. Image-to-PDF imports use Apple's generator to create new input documents.

Every snapshot is a full rewrite with unreachable objects collected, rather than an incremental update containing old content streams. Undo/redo uses in-memory snapshots. `NSDocument` manages atomic file saves, native autosaving, edited state, and macOS recovery. Existing filesystem backups and macOS document versions are outside the PDF's contents and are not erased by redaction; export a new redacted PDF when distributing it.

The C bridge catches MuPDF exceptions before returning to Swift. Native document windows, menus, dialogs, accessibility labels, printing, sharing, color controls, drawing, and PDFKit selection are provided by Apple frameworks. OCR uses a private PDFKit document off the main thread.

## Current limits

This is an initial development implementation, not a production-certified Acrobat replacement.

- Text correction supports horizontal, single-style lines and local edits that fit without overlapping other lines. It rejects mixed-style lines, unsupported glyphs, bidirectional/vertical/rotated text, and complex layouts. Embedded fonts may not contain new characters; explicit standard-font substitution is available. No paragraph reflow.
- Rotated or masked images and clipped/ambiguous image occurrences are rejected. Moving/replacing a supported source image removes it from its original content stream and creates an editable stamp at the new location.
- Page insertion preserves non-widget annotations but rejects source PDFs with form widgets; flatten those before merging. Imported outlines, global form trees, and accessibility structures are not merged. Existing destination structures are retained where the engine supports them. Full PDF/UA preservation is not guaranteed.
- Outline management adds/removes root bookmarks; nested existing outlines are displayed and preserved. Chapter inference depends on detectable textual headings or a contents page and cannot recover every book structure. Scanned books need text recognition first; uncertain entries are omitted. Links support HTTP(S), mailto, and internal page destinations. Complex actions and embedded PDF scripts are not executed.
- Certificate signing/verification, XFA, Office conversion, document comparison, cloud collaboration, rich document authoring, and new accessibility tagging are outside this release.
- Secure redaction removes overlapping text and entire intersecting images/vector objects. Pre-existing pending redactions must be handled in their originating app first. Metadata, attachments, other pages, OS backups, and other copies are not a document-wide sanitization operation.
- The implementation uses full-document candidate/undo snapshots, prioritizing rollback correctness over memory efficiency. Large-document responsiveness and memory usage need broader profiling before a stable release.
- Native control labels and keyboard navigation are implemented; full VoiceOver, crash recovery, real-world corpus, Preview/Acrobat interoperability, and cross-version testing are release gates, not yet certified.

## Tests

All 29 regression and native-document checks passed on the development machine. Apple Vision requires an unrestricted local process for its pixel buffers; the sandboxed OCR check failed while the ordinary local run passed.

The regression suite covers real text replacement and background retention, rollback/stale revisions, annotation persistence, undo snapshots, redaction/non-incremental output, encryption, flattening, page order/extraction, rotated crop geometry, image occurrence removal, form persistence, rejected merges, invisible OCR layers, malformed PDFs, and unsupported text. Test fixtures are generated locally and contain no private documents.

See `docs/RELEASE_CHECKLIST.md` for manual release checks.

## Distribution and source

```sh
bash scripts/package-source.sh
```

This creates a complete corresponding source archive including the pinned MuPDF sources and third-party dependencies. Distribute it alongside the app, preserving the MIT `LICENSE`, `licenses/AGPL-3.0.txt`, and `THIRD_PARTY_NOTICES.md`. The packaging script copies dependency licenses into the application bundle. The public repository pins MuPDF as a Git submodule; each binary release also includes a complete corresponding source archive so the release is buildable without separately fetching engine source.

For a Developer ID build set `CODE_SIGN_IDENTITY` when packaging. Hardened-runtime signing, notarization, and stapling are handled by `scripts/notarize.sh` after credentials are configured. These operations submit the app to Apple and are not performed by local development builds.
