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
        guard let paper else { return }
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
                    guard let self, self.paper != nil, self.visibleRevision == snapshot.number else { return }
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
        fitOutlineColumns()
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
    func fitOutlineColumns() {
        guard outline.tableColumns.count == 2 else { return }
        let width = sidebarScroll.contentSize.width
        guard width > 0 else { return }
        let titleWidth = max(70,width-outline.tableColumns[1].width)
        if abs(outline.tableColumns[0].width-titleWidth)>0.5 { outline.tableColumns[0].width = titleWidth }
        if abs(outline.frame.width-width)>0.5 { outline.setFrameSize(NSSize(width:width,height:outline.frame.height)) }
    }
    func outlineView(_ outlineView: NSOutlineView,viewFor tableColumn: NSTableColumn?,item: Any) -> NSView? {
        guard let node = item as? ChapterNode else { return nil }
        let cell = NSTableCellView()
        let isPage = tableColumn?.identifier.rawValue == "page"
        let value = isPage ? pdf.document?.page(at:node.chapter.page)?.label ?? String(node.chapter.page+1) : node.chapter.title
        let label = NSTextField(labelWithString:value)
        label.font = isPage ? .monospacedDigitSystemFont(ofSize:11,weight:.regular) : .systemFont(ofSize:12)
        label.textColor = isPage ? .secondaryLabelColor : .labelColor
        label.alignment = isPage ? .right : .left
        label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(label); cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:isPage ? 0 : 2),
            label.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:isPage ? -8 : -4),
            label.centerYAnchor.constraint(equalTo:cell.centerYAnchor)
        ])
        cell.toolTip = node.chapter.title
        cell.setAccessibilityLabel(isPage ? "Page "+value : node.chapter.title)
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let node = outline.item(atRow:outline.selectedRow) as? ChapterNode, let page = pdf.document?.page(at:node.chapter.page) else { return }
        pdf.go(to:page)
    }
}
