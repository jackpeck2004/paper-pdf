// SPDX-License-Identifier: MIT
import AppKit
import PDFKit

extension EditorController: NSMenuItemValidation {
    func makeViewModeMenu() -> NSMenu {
        let menu = NSMenu(title:"Page Layout")
        menu.delegate = self
        for (title,tag) in [("Single Page",0),("Continuous",1),("Two Pages",2),("Two Pages Continuous",3)] {
            let item = NSMenuItem(title:title,action:#selector(setViewMode(_:)),keyEquivalent:"")
            item.tag = tag; item.target = self; menu.addItem(item)
        }
        return menu
    }
    @objc func setViewMode(_ sender: NSMenuItem) { setDisplayMode(sender.tag) }
    func setDisplayMode(_ index: Int) {
        let modes: [PDFDisplayMode] = [.singlePage,.singlePageContinuous,.twoUp,.twoUpContinuous]
        guard modes.indices.contains(index) else { return }
        pdf.endTextEditing()
        let page = pdf.currentPage
        pdf.displayMode = modes[index]; pdf.autoScales = true
        if let page { pdf.go(to:page) }
        updateStatus()
    }
    @objc func singlePage(_ sender: Any?) { setDisplayMode(0) }
    @objc func continuousPages(_ sender: Any?) { setDisplayMode(1) }
    @objc func twoPages(_ sender: Any?) { setDisplayMode(2) }
    @objc func continuousTwoPages(_ sender: Any?) { setDisplayMode(3) }
    @objc func focusPageNumber(_ sender: Any?) {
        pageField.integerValue = currentPageIndex+1
        view.window?.makeFirstResponder(pageField); pageField.selectText(nil)
    }
    @objc func commitPageNumber(_ sender: Any?) {
        let input = pageField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        let pageIndex: Int?
        if let number = Int(input), number > 0, number <= (pdf.document?.pageCount ?? 0) { pageIndex = number-1 }
        else { pageIndex = (0..<(pdf.document?.pageCount ?? 0)).first { pdf.document?.page(at:$0)?.label?.localizedCaseInsensitiveCompare(input) == .orderedSame } }
        guard let pageIndex, let page = pdf.document?.page(at:pageIndex) else { NSSound.beep(); updateStatus(); return }
        pdf.endTextEditing(); pdf.go(to:page); view.window?.makeFirstResponder(pdf); updateStatus()
    }
    @objc func nextPage(_ sender: Any?) { navigatePage(currentPageIndex+1) }
    @objc func previousPage(_ sender: Any?) { navigatePage(currentPageIndex-1) }
    @objc func firstPage(_ sender: Any?) { navigatePage(0) }
    @objc func lastPage(_ sender: Any?) { navigatePage((pdf.document?.pageCount ?? 1)-1) }
    private func navigatePage(_ index: Int) {
        guard let document = pdf.document, index >= 0, index < document.pageCount, let page = document.page(at:index) else { return }
        pdf.endTextEditing(); pdf.go(to:page); updateStatus()
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(singlePage(_:)): item.state = pdf.displayMode == .singlePage ? .on : .off
        case #selector(continuousPages(_:)): item.state = pdf.displayMode == .singlePageContinuous ? .on : .off
        case #selector(twoPages(_:)): item.state = pdf.displayMode == .twoUp ? .on : .off
        case #selector(continuousTwoPages(_:)): item.state = pdf.displayMode == .twoUpContinuous ? .on : .off
        case #selector(nextPage(_:)): return currentPageIndex+1 < (pdf.document?.pageCount ?? 0)
        case #selector(previousPage(_:)): return currentPageIndex > 0
        default: break
        }
        return true
    }
}

extension EditorController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.action == #selector(chooseSidebarMode(_:)) {
            item.state = item.tag == sidebarMode.rawValue ? .on : .off
        }
        for item in menu.items where item.action == #selector(setViewMode(_:)) {
            let modes: [PDFDisplayMode] = [.singlePage,.singlePageContinuous,.twoUp,.twoUpContinuous]
            item.state = modes.indices.contains(item.tag) && modes[item.tag] == pdf.displayMode ? .on : .off
        }
    }
}

func readerViewMenuItems(target: AnyObject?) -> [NSMenuItem] {
    let definitions: [(String,Selector,String)] = [
        ("Single Page",#selector(EditorController.singlePage(_:)),"1"),
        ("Continuous",#selector(EditorController.continuousPages(_:)),"2"),
        ("Two Pages",#selector(EditorController.twoPages(_:)),"3"),
        ("Two Pages Continuous",#selector(EditorController.continuousTwoPages(_:)),"4")
    ]
    return definitions.map { title,selector,key in
        let item = NSMenuItem(title:title,action:selector,keyEquivalent:key); item.target = target; item.keyEquivalentModifierMask = .command; return item
    }
}
func readerGoMenuItems(target: AnyObject?) -> [NSMenuItem] {
    let definitions: [(String,Selector,String,NSEvent.ModifierFlags)] = [
        ("Go to Page…",#selector(EditorController.focusPageNumber(_:)),"g",[.command,.option]),
        ("Next Page",#selector(EditorController.nextPage(_:)),String(UnicodeScalar(NSDownArrowFunctionKey)!),[.command,.option]),
        ("Previous Page",#selector(EditorController.previousPage(_:)),String(UnicodeScalar(NSUpArrowFunctionKey)!),[.command,.option]),
        ("First Page",#selector(EditorController.firstPage(_:)),String(UnicodeScalar(NSHomeFunctionKey)!),[.command]),
        ("Last Page",#selector(EditorController.lastPage(_:)),String(UnicodeScalar(NSEndFunctionKey)!),[.command])
    ]
    var items = definitions.map { title,selector,key,modifiers in
        let item = NSMenuItem(title:title,action:selector,keyEquivalent:key); item.target = target; item.keyEquivalentModifierMask = modifiers; return item
    }
    for (key,modifiers) in [("l",NSEvent.ModifierFlags.command),("n",[.command,.shift])] {
        let alias = NSMenuItem(title:"Go to Page",action:#selector(EditorController.focusPageNumber(_:)),keyEquivalent:key)
        alias.keyEquivalentModifierMask = modifiers; alias.target = target; alias.isHidden = true; alias.allowsKeyEquivalentWhenHidden = true; items.append(alias)
    }
    return items
}
