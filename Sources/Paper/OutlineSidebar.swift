// SPDX-License-Identifier: MIT
import AppKit
import PDFKit
import PaperCore

final class ChapterNode {
    let chapter: BookChapter
    let children: [ChapterNode]
    init(_ chapter: BookChapter) { self.chapter = chapter; children = chapter.children.map(ChapterNode.init) }
    init(chapter: BookChapter,children: [ChapterNode]) { self.chapter = chapter; self.children = children }
    func filtered(_ query: String) -> ChapterNode? {
        if query.isEmpty || chapter.title.localizedCaseInsensitiveContains(query) { return self }
        let retained = children.compactMap { $0.filtered(query) }
        return retained.isEmpty ? nil : ChapterNode(chapter:chapter,children:retained)
    }
}

extension EditorController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func loadBookContents() {
        guard let document = pdf.document else { return }
        let embedded = BookOutline.embedded(in:document)
        if !embedded.isEmpty {
            chapters = embedded.map(ChapterNode.init); chapterRevision = visibleRevision; chapterSource = .embedded
            showChapters(); return
        }
        if chapterRevision == visibleRevision { showChapters(); return }
        contentsDescription.stringValue = "Finding chapters…"
        outline.reloadData()
        guard chapterRequest != visibleRevision else { return }
        do {
            let snapshot = try paper.store.snapshot()
            chapterRequest = snapshot.number
            DispatchQueue.global(qos:.userInitiated).async { [weak self] in
                let result = Result { try BookOutline.extract(data:snapshot.data) }
                DispatchQueue.main.async {
                    guard let self, self.visibleRevision == snapshot.number else { return }
                    self.chapterRequest = nil; self.chapterRevision = snapshot.number
                    switch result {
                    case .success(let contents): self.chapters = contents.chapters.map(ChapterNode.init); self.chapterSource = contents.source
                    case .failure: self.chapters = []; self.chapterSource = .unavailable
                    }
                    if self.sidebarMode.rawValue == 1 { self.showChapters() }
                }
            }
        } catch {
            chapters = []; chapterRevision = visibleRevision; chapterSource = .unavailable; showChapters()
        }
    }
    func showChapters() {
        visibleChapters = chapters.compactMap { $0.filtered(filter.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)) }
        switch chapterSource {
        case .embedded: contentsDescription.stringValue = "Document outline"
        case .contentsPage: contentsDescription.stringValue = "Detected from contents pages"
        case .headings: contentsDescription.stringValue = "Detected chapter headings"
        case .unavailable: contentsDescription.stringValue = "Contents"
        }
        outline.reloadData()
        for node in visibleChapters { outline.expandItem(node) }
        emptyContents.isHidden = !visibleChapters.isEmpty || sidebarMode.rawValue != 1
        emptyContents.stringValue = chapters.isEmpty ? "No chapters found\n\nScanned books need text recognition before chapters can be detected." : "No matching chapters"
    }
    func outlineView(_ outlineView: NSOutlineView,numberOfChildrenOfItem item: Any?) -> Int {
        (item as? ChapterNode)?.children.count ?? visibleChapters.count
    }
    func outlineView(_ outlineView: NSOutlineView,child index: Int,ofItem item: Any?) -> Any {
        (item as? ChapterNode)?.children[index] ?? visibleChapters[index]
    }
    func outlineView(_ outlineView: NSOutlineView,isItemExpandable item: Any) -> Bool { !((item as? ChapterNode)?.children.isEmpty ?? true) }
    func outlineView(_ outlineView: NSOutlineView,viewFor tableColumn: NSTableColumn?,item: Any) -> NSView? {
        guard let node = item as? ChapterNode else { return nil }
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString:node.chapter.title); title.font = .systemFont(ofSize:12); title.lineBreakMode = .byTruncatingTail
        let page = NSTextField(labelWithString:pdf.document?.page(at:node.chapter.page)?.label ?? String(node.chapter.page+1)); page.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); page.textColor = .secondaryLabelColor
        page.setContentHuggingPriority(.required,for:.horizontal); page.setContentCompressionResistancePriority(.required,for:.horizontal)
        let row = NSStackView(views:[title,page]); row.orientation = .horizontal; row.spacing = 10; row.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(row); cell.textField = title
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:2),row.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-8),row.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
        cell.setAccessibilityLabel(node.chapter.title+", page "+page.stringValue)
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let node = outline.item(atRow:outline.selectedRow) as? ChapterNode, let page = pdf.document?.page(at:node.chapter.page) else { return }
        pdf.go(to:page)
    }
}
