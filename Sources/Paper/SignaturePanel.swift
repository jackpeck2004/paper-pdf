// SPDX-License-Identifier: MIT
import AppKit

final class SignatureDrawing: NSView {
    var strokes: [[CGPoint]] = []
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { strokes.append([convert(event.locationInWindow,from:nil)]); needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { guard !strokes.isEmpty else { return }; strokes[strokes.count-1].append(convert(event.locationInWindow,from:nil)); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        drawStrokes()
    }
    func drawStrokes() {
        NSColor.black.setStroke()
        for stroke in strokes where stroke.count > 1 {
            let path = NSBezierPath(); path.lineWidth = 2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to:stroke[0]); stroke.dropFirst().forEach(path.line); path.stroke()
        }
    }
    func png() -> Data? {
        guard strokes.contains(where: { $0.count > 1 }) else { return nil }
        let image = NSImage(size:bounds.size,flipped:true) { [self] _ in drawStrokes(); return true }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff) else { return nil }
        return rep.representation(using:.png,properties:[:])
    }
}
enum SignaturePanel {
    static func choose() -> Data? {
        let manager = FileManager.default
        let folder = manager.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Paper/Signatures",isDirectory:true)
        let saved = ((try? manager.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []).filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let alert = NSAlert(); alert.messageText = "Visual Signature"; alert.informativeText = "Draw below or reuse a saved signature. Signatures are saved privately on this Mac. These are visual marks, not certificate signatures."
        alert.addButton(withTitle:"Use Signature"); alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:"Import Image…")
        let picker = NSPopUpButton(); picker.addItem(withTitle:"Draw a new signature"); picker.addItems(withTitles:saved.enumerated().map { "Saved signature \($0.offset+1)" })
        let canvas = SignatureDrawing(frame:NSRect(x:0,y:0,width:400,height:150)); canvas.setAccessibilityLabel("Draw your signature with the mouse or trackpad; import an image as an alternative")
        canvas.widthAnchor.constraint(equalToConstant:400).isActive = true; canvas.heightAnchor.constraint(equalToConstant:150).isActive = true
        let stack = NSStackView(views:[picker,canvas]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; stack.frame = NSRect(x:0,y:0,width:400,height:190); alert.accessoryView = stack
        let response = alert.runModal()
        if response == .alertSecondButtonReturn { return nil }
        do {
            let data: Data
            if response == .alertThirdButtonReturn {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.tiff]
                guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf:url), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff), let png = rep.representation(using:.png,properties:[:]) else { return nil }
                data = png
            } else if picker.indexOfSelectedItem > 0 { return try Data(contentsOf:saved[picker.indexOfSelectedItem-1]) }
            else {
                guard let png = canvas.png() else { let a = NSAlert(); a.messageText = "Draw a signature first"; a.runModal(); return nil }; data = png
            }
            try manager.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let url = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            try data.write(to:url,options:.atomic); try manager.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
            return data
        } catch { NSApp.presentError(error); return nil }
    }
}
