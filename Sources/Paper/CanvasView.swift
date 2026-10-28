// SPDX-License-Identifier: MIT
import AppKit
import PDFKit
import PaperCore

enum EditorTool: String, CaseIterable {
    case select = "Select", highlight = "Highlight", underline = "Underline", strike = "Strikethrough"
    case note = "Note", text = "Text Box", rectangle = "Rectangle", oval = "Oval", arrow = "Arrow", ink = "Draw"
    case editImage = "Edit Image"
    case correct = "Correct Text", image = "Place Image", signature = "Signature", crop = "Crop", redact = "Redact", link = "Link", form = "Fill Form"
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strike: return "strikethrough"
        case .note: return "note.text"
        case .text: return "textformat.alt"
        case .rectangle: return "rectangle"
        case .oval: return "circle"
        case .arrow: return "arrow.up.right"
        case .ink: return "pencil.tip"
        case .editImage: return "photo.badge.checkmark"
        case .correct: return "character.cursor.ibeam"
        case .image: return "photo.badge.plus"
        case .signature: return "signature"
        case .crop: return "crop"
        case .redact: return "rectangle.fill"
        case .link: return "link"
        case .form: return "list.bullet.rectangle"
        }
    }
    var hint: String {
        switch self {
        case .select: return "Select text to copy or review. Click an annotation to inspect it."
        case .highlight, .underline, .strike: return "Select text. The selected markup is applied when you release."
        case .note: return "Click the page to leave a note."
        case .correct: return "Click a line to correct its text. Complex or overlapping lines are protected."
        case .editImage: return "Click an existing image to move, resize, replace, or delete it."
        case .image: return "Drag an area, then choose an image."
        case .signature: return "Drag an area to place a drawn or imported visual signature."
        case .crop: return "Drag the visible page area to keep. Cropping hides content; use Redact to remove it."
        case .redact: return "Drag an area to permanently remove content from saved output."
        case .text: return "Click to type, or drag a text area. Apply with ⌘Return; click existing text boxes with Select to edit."
        case .link: return "Drag a link area, then enter an HTTPS URL or #page=2 destination."
        case .form: return "Click a standard form field to change its value."
        default: return "Drag on a page to add \(rawValue.lowercased())."
        }
    }
    var annotationKind: String? {
        switch self {
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strike: return "StrikeOut"
        case .note: return "Text"
        case .text: return "FreeText"
        case .rectangle: return "Square"
        case .oval: return "Circle"
        case .arrow: return "Line"
        case .ink: return "Ink"
        default: return nil
        }
    }
}
final class CanvasView: PDFView {
    var tool: EditorTool = .select
    var onGesture: ((EditorTool,PDFPage,CGRect,[CGPoint]) -> Void)?
    var onSelection: ((EditorTool) -> Void)?
    var onAnnotation: ((PDFPage,PDFAnnotation) -> Void)?
    var onFiles: (([URL]) -> Void)?
    var inlineEditor: InlineTextEditor?
    var inlinePage: PDFPage?
    var inlineBounds = CGRect.zero
    var inlineSize: CGFloat = 14
    var inlineMultiline = false
    private var scrollObserver: NSObjectProtocol?
    override init(frame: NSRect) {
        super.init(frame:frame)
        scrollObserver = NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:nil,queue:.main) { [weak self] event in
            guard let self, let clip = event.object as? NSClipView, clip.isDescendant(of:self) else { return }
            self.positionTextEditor()
        }
    }
    required init?(coder: NSCoder) { super.init(coder:coder) }
    deinit { if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) } }
    override func layout() { super.layout(); positionTextEditor() }
    private var start: NSPoint?
    private var trail: [NSPoint] = []
    private var gesturePage: PDFPage?
    private var dragRect: CGRect?
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        guard let page = page(for:point,nearest:false) else { super.mouseDown(with:event); return }
        let local = convert(point,to:page)
        if tool == .select {
            if let annotation = page.annotations.reversed().first(where: { $0.bounds.contains(local) }) {
                onAnnotation?(page,annotation); return
            }
            super.mouseDown(with:event); return
        }
        if [.highlight,.underline,.strike].contains(tool) {
            super.mouseDown(with:event)
            // PDFKit may consume mouse-up inside its own selection tracking loop.
            if NSEvent.pressedMouseButtons == 0 { onSelection?(tool) }
            return
        }
        start = point; trail = [point]; gesturePage = page
        if [.note,.correct,.form,.editImage].contains(tool) {
            onGesture?(tool,page,CGRect(origin:local,size:.zero),[])
            start = nil; gesturePage = nil
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { super.mouseDragged(with:event); return }
        let end = convert(event.locationInWindow,from:nil)
        trail.append(end)
        dragRect = CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(start.x-end.x),height:abs(start.y-end.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start, let page = gesturePage else {
            if tool != .select && [.highlight,.underline,.strike].contains(tool) {
                super.mouseUp(with:event); onSelection?(tool)
            } else if tool == .select { super.mouseUp(with:event) }
            return
        }
        let end = convert(event.locationInWindow,from:nil)
        let a = convert(start,to:page), b = convert(end,to:page)
        let points = (trail+[end]).map { convert($0,to:page) }
        let r: CGRect
        if tool == .ink {
            let xs = points.map(\.x), ys = points.map(\.y)
            r = CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
        } else { r = CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y)) }
        self.start = nil; gesturePage = nil; dragRect = nil; trail = []; needsDisplay = true
        if tool == .text || (r.width > 2 && r.height > 2) || (tool == .ink && points.count > 1) || (tool == .arrow && (r.width > 2 || r.height > 2)) { onGesture?(tool,page,r,points) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title,action) in [("Copy",#selector(NSText.copy(_:))),("Highlight Selection",#selector(EditorController.highlight(_:))),("Comment on Selection…",#selector(EditorController.commentSelection(_:))),("Correct Selected Text…",#selector(EditorController.correctSelection(_:)))] {
            menu.addItem(withTitle:title,action:action,keyEquivalent:"")
        }
        return menu
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let dragRect {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); dragRect.fill()
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect:dragRect); path.lineWidth = 1; path.setLineDash([4,3],count:2,phase:0); path.stroke()
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFiles?(urls); return true
    }
}
