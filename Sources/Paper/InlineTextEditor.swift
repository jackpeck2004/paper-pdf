// SPDX-License-Identifier: MIT
import AppKit
import PDFKit

final class EditingTextView: NSTextView {
    var accept: (() -> Void)?
    var cancel: (() -> Void)?
    var multiline = false
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?(); return }
        if event.keyCode == 36 && (!multiline || event.modifierFlags.contains(.command)) { accept?(); return }
        super.keyDown(with:event)
    }
}

/// A real text editor anchored to the selected PDF region; it follows zoom/scroll.
final class InlineTextEditor: NSView {
    let text = EditingTextView()
    private let editorScroll = NSScrollView()
    private let apply = NSButton(title:"Apply",target:nil,action:nil)
    private let cancel = NSButton(title:"Cancel",target:nil,action:nil)
    var onApply: ((String) -> Void)?
    var onCancel: (() -> Void)?
    init(value: String, font: NSFont, color: NSColor, multiline: Bool) {
        super.init(frame:.zero)
        wantsLayer = true
        editorScroll.wantsLayer = true; editorScroll.layer?.cornerRadius = 5
        editorScroll.layer?.borderColor = NSColor.controlAccentColor.cgColor; editorScroll.layer?.borderWidth = 1.5
        text.isRichText = false; text.font = font; text.textColor = color; text.string = value
        text.backgroundColor = .textBackgroundColor; text.textContainerInset = NSSize(width:5,height:3)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.multiline = multiline
        text.setAccessibilityLabel(multiline ? "Text annotation" : "Edit PDF text")
        editorScroll.documentView = text; editorScroll.hasVerticalScroller = multiline; editorScroll.borderType = .noBorder
        apply.target = self; apply.action = #selector(commit); apply.bezelStyle = .rounded; apply.controlSize = .small
        cancel.target = self; cancel.action = #selector(dismiss); cancel.bezelStyle = .rounded; cancel.controlSize = .small
        apply.keyEquivalent = "\r"
        let buttons = NSStackView(views:[cancel,apply]); buttons.orientation = .horizontal; buttons.spacing = 6
        buttons.edgeInsets = NSEdgeInsets(top:4,left:8,bottom:4,right:8)
        let controls = NativeGlass.surface(content:buttons,cornerRadius:16)
        for child in [editorScroll,controls] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        NSLayoutConstraint.activate([
            editorScroll.topAnchor.constraint(equalTo:topAnchor,constant:3),editorScroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:3),editorScroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-3),
            editorScroll.bottomAnchor.constraint(equalTo:controls.topAnchor,constant:-4),
            controls.trailingAnchor.constraint(equalTo:trailingAnchor),controls.bottomAnchor.constraint(equalTo:bottomAnchor),controls.heightAnchor.constraint(equalToConstant:32)
        ])
        text.accept = { [weak self] in self?.commit() }; text.cancel = { [weak self] in self?.dismiss() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc func commit() { onApply?(text.string) }
    @objc func dismiss() { onCancel?() }
}

extension CanvasView {
    func beginTextEditing(on page: PDFPage, bounds: CGRect, value: String, size: CGFloat, color: NSColor, multiline: Bool, commit: @escaping (String) -> Void) {
        endTextEditing()
        let editor = InlineTextEditor(value:value,font:.systemFont(ofSize:max(11,size*scaleFactor)),color:color,multiline:multiline)
        inlineEditor = editor; inlinePage = page; inlineBounds = bounds; inlineSize = size; inlineMultiline = multiline
        editor.onApply = { [weak self] value in self?.endTextEditing(); commit(value) }
        editor.onCancel = { [weak self] in self?.endTextEditing() }
        addSubview(editor); positionTextEditor()
        window?.makeFirstResponder(editor.text); editor.text.selectAll(nil)
    }
    func endTextEditing() {
        inlineEditor?.removeFromSuperview(); inlineEditor = nil; inlinePage = nil
    }
    func positionTextEditor() {
        guard let editor = inlineEditor, let page = inlinePage, page.document === document else { return }
        let r = convert(inlineBounds,from:page)
        let width = min(max(200,r.width+16),max(200,bounds.width-24))
        let height = max(inlineMultiline ? 120 : 62,r.height+42)
        editor.frame = CGRect(x:max(8,min(r.minX-5,bounds.width-width-8)),y:r.maxY-height+5,width:width,height:height)
        editor.text.font = .systemFont(ofSize:max(11,inlineSize*scaleFactor))
    }
}
