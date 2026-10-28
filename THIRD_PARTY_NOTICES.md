# Third-party components

Paper’s original source code, tests, build scripts, and project-authored documentation are licensed under the MIT License in `LICENSE`. Copyright © 2026 Paper contributors. This grant does not relicense any third-party code or Apple system frameworks.

The distributed application statically links MuPDF. This combined distribution remains subject to MuPDF’s GNU AGPL v3-or-later requirements; the application binary is not an MIT-only distribution. The AGPL text is retained in `licenses/AGPL-3.0.txt`, and corresponding engine and application source must accompany distribution as described below. Paper’s original MIT license and copyright notices must also be retained.

MuPDF 1.28.5, copyright Artifex Software, Inc., is statically linked under GNU AGPL version 3 or later. Upstream source: https://github.com/ArtifexSoftware/mupdf at commit `8ad45e92f0935d3d87f1db3f873086472a5e1b24`.

MuPDF includes third-party font, image, compression, shaping, parsing, and rendering components. Their individual licenses and notices are retained in `Vendor/mupdf` and copied, with their relative directory paths, into `Paper.app/Contents/Resources/Licenses/MuPDF` by the packaging script. The built dependency configuration disables Tesseract, Leptonica, ZXing, Zint, curl, GLUT, and external crypto integration; OCR uses Apple's on-device Vision framework. The source bundle includes upstream source and its pinned submodules, including components that are not linked.

Apple AppKit, PDFKit, CoreGraphics, CoreText, and Vision are macOS system frameworks, supplied by Apple and not redistributed by this project.

Source distribution: run `bash scripts/package-source.sh`. Distribute the corresponding source archive alongside any app binary, with these notices and the AGPL license intact. No proprietary PDF SDK or cloud API is used.
