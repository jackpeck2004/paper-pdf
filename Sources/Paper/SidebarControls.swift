// SPDX-License-Identifier: MIT
import AppKit
import PDFKit
import PaperCore

enum SidebarMode: Int, CaseIterable {
    case pages, outline, notes
    var title: String {
        switch self {
        case .pages: return "Thumbnails"
        case .outline: return "Table of Contents"
        case .notes: return "Highlights and Notes"
        }
    }
}

extension EditorController {
    func makeSidebarMenu() -> NSMenu {
        let menu = NSMenu(title:"Sidebar"); menu.delegate = self
        for mode in SidebarMode.allCases {
            let item = NSMenuItem(title:mode.title,action:#selector(chooseSidebarMode(_:)),keyEquivalent:"")
            item.target = self; item.tag = mode.rawValue; menu.addItem(item)
        }
        return menu
    }
    @objc func chooseSidebarMode(_ sender: NSMenuItem) {
        guard let mode = SidebarMode(rawValue:sender.tag) else { return }
        sidebarMode = mode; sidebarItem.isCollapsed = false; filter.stringValue = ""; reloadSidebar()
    }
    func commitThumbnailOrder() {
        guard let paper else { return }
        guard !isRefreshing, let document = pdf.document else { return }
        let order = (0..<document.pageCount).compactMap { document.page(at:$0).flatMap { pageIdentityToIndex[ObjectIdentifier($0)] } }
        guard order.count == pageIdentityToIndex.count, Set(order).count == order.count else {
            // Native cross-document drops aren't a canonical edit. Restore the
            // viewer; importing through the Pages menu preserves engine invariants.
            if let snapshot = try? paper.store.snapshot() { display(snapshot) }
            return
        }
        guard order != Array(0..<order.count) else { return }
        if !paper.perform("Reorder Pages",expectedRevision:visibleRevision,{ try $0.reorder(order) }), let snapshot = try? paper.store.snapshot() { display(snapshot) }
    }
}
