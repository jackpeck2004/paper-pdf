// SPDX-License-Identifier: MIT
import AppKit

/// Use the OS material so tint, contrast, reduced transparency and appearance
/// follow the user's macOS settings. Older Macs retain their native materials.
enum NativeGlass {
    static func surface(content: NSView,cornerRadius: CGFloat = 20) -> NSView {
        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular; glass.cornerRadius = cornerRadius; glass.contentView = content
            surface = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .hudWindow; material.blendingMode = .withinWindow; material.state = .followsWindowActiveState
            material.wantsLayer = true; material.layer?.cornerRadius = cornerRadius; material.layer?.masksToBounds = true
            material.addSubview(content); surface = material
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:surface.leadingAnchor),content.trailingAnchor.constraint(equalTo:surface.trailingAnchor),content.topAnchor.constraint(equalTo:surface.topAnchor),content.bottomAnchor.constraint(equalTo:surface.bottomAnchor)])
        return surface
    }
}
