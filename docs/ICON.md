# Paper app icon

The selected artwork was generated with the built-in ImageGen tool, then converted to the standard macOS icon resolutions using Apple's `sips` and `iconutil`. No image-generation API or service is used by the running app.

- Selected master: `Resources/AppIcon.png`
- Packaged macOS resource: `Resources/AppIcon.icns`
- Initial artwork and cleanup variant: `Resources/PaperIcon.png`, `Resources/PaperIcon-v2.png`
- Rebuild: `bash scripts/build-icon.sh`

The app includes 16, 32, 64, 128, 256, 512, and 1024-pixel representations, including the standard Retina variants. `CFBundleIconFile` references `AppIcon`. This is a raster icon asset; the in-app Liquid Glass controls use native AppKit materials independently.

## Original prompt

Create a single production-ready macOS desktop app icon for a clean native PDF editor named Paper. Square 1024 x 1024 composition, front-on orthographic, not a perspective mockup. A softly rounded translucent frosted-glass squircle tile, pearl white with a very restrained ice-blue inner gradient and delicate beveled edge, containing one elegant folded white document sheet with just three short embossed gray text lines. A single vivid coral-red editing pencil crosses the bottom-right corner of the document diagonally, simple and recognizable. This should feel at home beside Apple's macOS 26 Liquid Glass app icons: refined, tactile, calm, minimal, crisp silhouette, soft top-left lighting and subtle depth. Center the squircle tile at about 88% canvas size with balanced transparent margins; actual transparent alpha background outside the icon silhouette. The document and pencil must remain legible at small Dock sizes. No text, no letters, no PDF label, no word Paper, no Apple logo, no extra objects, no multiple variants, no border around the canvas, no scene, no watermark.

## Cleanup prompt

Edit this app icon only to clean its outer silhouette and alpha. Preserve the glass-blue tile, white folded document, gray embossed lines, coral pencil, lighting, composition and relative proportions exactly. The outer perimeter must be ONE perfectly smooth, clean rounded-square squircle boundary. Remove ALL ragged white fragments, speckles, detached pixels, halos, grit and noisy edges outside the tile. The space outside the smooth squircle must be completely transparent, with no shadow, no glow and no detached marks. Keep a consistent transparent margin around the centered icon. Crisp professional macOS Dock icon alpha edges, not a fuzzy cutout. Do not add text or change the central design.
