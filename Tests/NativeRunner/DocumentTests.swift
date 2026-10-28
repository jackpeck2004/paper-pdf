import AppKit
import PDFKit
import PaperCore

final class DocumentTests: XCTestCase {
    func testViewerNotificationsAfterDocumentRelease() throws {
        weak var releasedDocument: PaperDocument?
        let controller: EditorController = try autoreleasepool {
            let document = PaperDocument()
            releasedDocument = document
            try document.read(from:EngineTests.fixture(),ofType:"com.adobe.pdf")
            let controller = EditorController(document:document)
            controller.loadViewIfNeeded()
            let page = try XCTUnwrap(controller.pdf.document?.page(at:0))
            controller.gesture(.text,page:page,bounds:CGRect(x:40,y:40,width:180,height:24),points:[])
            XCTAssertTrue(controller.pdf.inlineEditor != nil)
            return controller
        }
        XCTAssertTrue(releasedDocument == nil)
        // AppKit can retain the content controller while a closing window lays
        // out. PDFKit still posts page/scale notifications during that layout.
        NotificationCenter.default.post(name:.PDFViewScaleChanged,object:controller.pdf)
        NotificationCenter.default.post(name:.PDFViewPageChanged,object:controller.pdf)
        controller.pdf.setFrameSize(NSSize(width:700,height:500))
        controller.updateStatus()
        controller.commitThumbnailOrder()
        controller.rotatePage(nil)
        controller.pdf.inlineEditor?.commit()
        XCTAssertTrue(controller.pdf.inlineEditor == nil)
    }
    func testNativeWindowCommandsAndUndoRedo() throws {
        let document = PaperDocument()
        try document.read(from:EngineTests.fixture(),ofType:"com.adobe.pdf")
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorController)
        XCTAssertEqual(controller.pdf.document?.pageCount,1)
        let undo = try XCTUnwrap(document.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        controller.insertBlank(nil)
        undo.endUndoGrouping()
        XCTAssertEqual(document.store.read { $0.pageCount },2)
        XCTAssertEqual(controller.pdf.document?.pageCount,2)
        XCTAssertTrue(document.isDocumentEdited)
        undo.undo()
        XCTAssertEqual(document.store.read { $0.pageCount },1)
        XCTAssertEqual(controller.pdf.document?.pageCount,1)
        undo.redo()
        XCTAssertEqual(document.store.read { $0.pageCount },2)
        // Drive a real native controller action using PDFKit selection geometry.
        let first = try XCTUnwrap(controller.pdf.document?.page(at:0))
        let selection = try XCTUnwrap(first.selection(for:first.bounds(for:.cropBox)))
        controller.pdf.setCurrentSelection(selection,animate:false)
        undo.beginUndoGrouping(); controller.highlight(nil); undo.endUndoGrouping()
        let exported = try document.data(ofType:"com.adobe.pdf")
        XCTAssertTrue(PDFDocument(data:exported)?.page(at:0)?.annotations.contains { $0.type == "Highlight" } == true)
        XCTAssertTrue(controller.pdf.document?.page(at:0)?.annotations.allSatisfy(\.isReadOnly) == true)
        document.updateChangeCount(.changeCleared)
    }
    func testInlineTextEditingAndIconToolbar() throws {
        let document = PaperDocument()
        try document.read(from:EngineTests.fixture(),ofType:"com.adobe.pdf")
        document.makeWindowControllers()
        defer { document.updateChangeCount(.changeCleared); document.close() }
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorController)
        let toolbar = try XCTUnwrap(document.windowControllers.first?.window?.toolbar)
        XCTAssertFalse(controller.toolbarDefaultItemIdentifiers(toolbar).contains(.init("tool")))
        controller.selectTool(.correct)
        XCTAssertEqual(controller.pdf.tool,.correct)
        XCTAssertFalse(controller.markupScroll.isHidden)
        XCTAssertTrue(controller.inspectorItem.isCollapsed)
        let page = try XCTUnwrap(controller.pdf.document?.page(at:0))
        let line = try XCTUnwrap(document.store.read { try $0.lines(page:0).first })
        controller.correct(page:page,at:CGPoint(x:line.bounds.midX,y:line.bounds.midY))
        let editor = try XCTUnwrap(controller.pdf.inlineEditor)
        editor.text.string = "Inline correction"
        let undo = try XCTUnwrap(document.undoManager)
        undo.groupsByEvent = false; undo.beginUndoGrouping(); editor.commit(); undo.endUndoGrouping()
        XCTAssertTrue(controller.pdf.inlineEditor == nil)
        XCTAssertTrue(controller.pdf.document?.string?.contains("Inline correction") == true)
        undo.undo()
        XCTAssertTrue(controller.pdf.document?.string?.contains("Original secret") == true)
        let restored = try XCTUnwrap(controller.pdf.document?.page(at:0))
        controller.correct(page:restored,at:CGPoint(x:line.bounds.midX,y:line.bounds.midY))
        controller.pdf.inlineEditor?.text.string = "Discard me"
        controller.pdf.inlineEditor?.dismiss()
        XCTAssertTrue(controller.pdf.document?.string?.contains("Original secret") == true)
        XCTAssertFalse(controller.pdf.document?.string?.contains("Discard me") == true)
    }
    func testOutlineHierarchyNavigatesToChapter() throws {
        let document = PaperDocument()
        try document.read(from:EngineTests.fixture(),ofType:"com.adobe.pdf")
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorController)
        controller.sidebarMode = .outline
        controller.chapters = [ChapterNode(BookChapter(title:"Part One",page:0,children:[BookChapter(title:"First Chapter",page:0)]))]
        controller.chapterSource = .headings
        controller.showChapters()
        XCTAssertTrue(controller.outline.isItemExpanded(controller.chapters[0]))
        XCTAssertEqual(controller.outline.numberOfRows,2)
        controller.outline.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        XCTAssertEqual(controller.currentPageIndex,0)
        controller.filter.stringValue = "First Chapter"
        controller.showChapters()
        XCTAssertEqual(controller.visibleChapters.count,1)
        XCTAssertEqual(controller.visibleChapters[0].children.count,1)
    }
    func testReaderMenuShortcutsDispatchToAllViewModes() throws {
        let document = PaperDocument()
        try document.read(from:BookOutlineTests.book([BookOutlineTests.page("Chapter 1"),BookOutlineTests.page("Chapter 2"),BookOutlineTests.page("Chapter 3")]),ofType:"com.adobe.pdf")
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorController)
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        window.makeFirstResponder(controller.pdf)
        let menu = NSMenu(); menu.autoenablesItems = false
        readerViewMenuItems(target:controller).forEach(menu.addItem)
        let modes: [PDFDisplayMode] = [.singlePage,.singlePageContinuous,.twoUp,.twoUpContinuous]
        for (i,mode) in modes.enumerated() {
            let key = String(i+1)
            let event = try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:0))
            XCTAssertTrue(menu.performKeyEquivalent(with:event))
            XCTAssertEqual(controller.pdf.displayMode,mode)
        }
        let dropdown = controller.makeViewModeMenu()
        XCTAssertEqual(dropdown.items.count,4)
        _ = dropdown.items[0].target?.perform(try XCTUnwrap(dropdown.items[0].action),with:dropdown.items[0])
        XCTAssertEqual(controller.pdf.displayMode,.singlePage)
        controller.menuNeedsUpdate(dropdown)
        XCTAssertEqual(dropdown.items[0].state,.on)
        let viewItem = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "viewMode" } as? NSMenuToolbarItem)
        XCTAssertTrue(viewItem.showsIndicator)
    }
    func testGoToPageFieldAndShortcutAliases() throws {
        let document = PaperDocument()
        try document.read(from:BookOutlineTests.book([BookOutlineTests.page("Chapter 1"),BookOutlineTests.page("Chapter 2"),BookOutlineTests.page("Chapter 3")]),ofType:"com.adobe.pdf")
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorController)
        controller.setDisplayMode(0)
        controller.pageField.stringValue = "3"; controller.commitPageNumber(nil)
        XCTAssertEqual(controller.currentPageIndex,2)
        XCTAssertEqual(controller.pageField.integerValue,3)
        controller.firstPage(nil); XCTAssertEqual(controller.currentPageIndex,0)
        controller.nextPage(nil); XCTAssertEqual(controller.currentPageIndex,1)
        controller.previousPage(nil); XCTAssertEqual(controller.currentPageIndex,0)
        controller.lastPage(nil); XCTAssertEqual(controller.currentPageIndex,2)
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        window.makeFirstResponder(controller.pdf)
        XCTAssertFalse(controller.pdf.responds(to:#selector(EditorController.focusPageNumber(_:))))
        XCTAssertTrue(controller.pdf.tryToPerform(#selector(EditorController.focusPageNumber(_:)),with:nil))
        let commands = readerGoMenuItems(target:controller)
        XCTAssertTrue(commands.contains { $0.keyEquivalent == "g" && $0.keyEquivalentModifierMask == [.command,.option] })
        XCTAssertTrue(commands.contains { $0.keyEquivalent == "l" && $0.allowsKeyEquivalentWhenHidden })
        XCTAssertTrue(commands.contains { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == [.command,.shift] })
        let before = controller.currentPageIndex
        controller.pageField.stringValue = "9999"; controller.commitPageNumber(nil)
        XCTAssertEqual(controller.currentPageIndex,before)
    }
    func testResponsiveLayoutUsesNativeGlass() throws {
        let document = PaperDocument()
        try document.read(from:EngineTests.fixture(),ofType:"com.adobe.pdf")
        document.makeWindowControllers()
        defer { document.close() }
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        let controller = try XCTUnwrap(window.contentViewController as? EditorController)
        for size in [CGSize(width:1120,height:800),CGSize(width:820,height:560)] {
            window.setContentSize(size); controller.showMarkup(); controller.showInspector()
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(controller.pdf.frame.width,CGFloat(0))
            XCTAssertGreaterThan(controller.markupSurface.frame.width,CGFloat(0))
            XCTAssertEqual(controller.markupSurface.frame.height,CGFloat(42),accuracy:0.5)
            XCTAssertFalse(controller.view.hasAmbiguousLayout)
            XCTAssertGreaterThan(controller.markupScroll.documentView?.frame.width ?? 0,CGFloat(100))
            for button in controller.toolButtons.values.flatMap({ $0 }) {
                XCTAssertGreaterThan(button.frame.width,CGFloat(20))
                XCTAssertGreaterThan(button.frame.height,CGFloat(20))
            }
        }
        if #available(macOS 26.0, *) { XCTAssertTrue(controller.markupSurface is NSGlassEffectView) }
        // These renders are generated from the app's own view hierarchy in the
        // test process; they do not capture or inspect the user's screen.
        if let directory = ProcessInfo.processInfo.environment["PAPER_LAYOUT_PREVIEWS"] {
            window.setContentSize(CGSize(width:1120,height:800)); controller.inspectorItem.isCollapsed = true
            controller.view.layoutSubtreeIfNeeded()
            if let rep = controller.view.bitmapImageRepForCachingDisplay(in:controller.view.bounds) {
                controller.view.cacheDisplay(in:controller.view.bounds,to:rep)
                if let data = rep.representation(using:.png,properties:[:]) { try data.write(to:URL(fileURLWithPath:directory).appendingPathComponent("editor-layout.png")) }
            }
        }
    }
    func testPreviewSidebarAndSinglePageControl() throws {
        let document = PaperDocument()
        try document.read(from:EngineTests.fixture(),ofType:"com.adobe.pdf")
        document.makeWindowControllers()
        defer { document.close() }
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        let controller = try XCTUnwrap(window.contentViewController as? EditorController)
        XCTAssertFalse(controller.toolbarDefaultItemIdentifiers(try XCTUnwrap(window.toolbar)).contains(.init("page")))
        XCTAssertTrue(controller.pageField.isDescendant(of:controller.documentArea))
        XCTAssertTrue(controller.thumbnails.pdfView === controller.pdf)
        XCTAssertEqual(controller.thumbnails.maximumNumberOfColumns,1)
        XCTAssertGreaterThan(controller.thumbnails.thumbnailSize.width,CGFloat(100))
        XCTAssertTrue(controller.thumbnails.allowsMultipleSelection)
        XCTAssertTrue(controller.thumbnails.allowsDragging)
        XCTAssertTrue(controller.sidebarScroll.isHidden)
        XCTAssertFalse(controller.thumbnails.isHidden)
        let menu = controller.makeSidebarMenu()
        XCTAssertEqual(menu.items.map(\.title),["Thumbnails","Table of Contents","Highlights and Notes"])
        controller.chooseSidebarMode(menu.items[2])
        XCTAssertEqual(controller.sidebarMode,.notes)
        XCTAssertTrue(controller.thumbnails.isHidden)
        XCTAssertFalse(controller.sidebarScroll.isHidden)
        controller.chooseSidebarMode(menu.items[0])
        XCTAssertFalse(controller.thumbnails.isHidden)
        XCTAssertFalse(controller.status.stringValue.contains("of"))
    }
    func testNativeThumbnailReorderCommitsAndUndoes() throws {
        let document = PaperDocument()
        try document.read(from:BookOutlineTests.book([BookOutlineTests.page("Chapter 1"),BookOutlineTests.page("Chapter 2")]),ofType:"com.adobe.pdf")
        document.makeWindowControllers()
        defer { document.updateChangeCount(.changeCleared); document.close() }
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorController)
        let snapshot = try XCTUnwrap(controller.pdf.document)
        let second = try XCTUnwrap(snapshot.page(at:1))
        let undo = try XCTUnwrap(document.undoManager)
        undo.groupsByEvent = false; undo.beginUndoGrouping()
        snapshot.removePage(at:1); snapshot.insert(second,at:0)
        NotificationCenter.default.post(name:.PDFThumbnailViewDocumentEdited,object:controller.thumbnails)
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        undo.endUndoGrouping()
        XCTAssertTrue(controller.pdf.document?.page(at:0)?.string?.contains("Chapter 2") == true)
        XCTAssertTrue(PDFDocument(data:try document.store.snapshot().data)?.page(at:0)?.string?.contains("Chapter 2") == true)
        undo.undo()
        XCTAssertTrue(controller.pdf.document?.page(at:0)?.string?.contains("Chapter 1") == true)
    }
    func testOutlineUsesFullWidthAndTrailingPageColumn() throws {
        let document = PaperDocument()
        try document.read(from:EngineTests.fixture(),ofType:"com.adobe.pdf")
        document.makeWindowControllers()
        defer { document.close() }
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        let controller = try XCTUnwrap(window.contentViewController as? EditorController)
        controller.sidebarMode = .outline
        controller.chapters = [ChapterNode(BookChapter(title:"Wide chapter title that should use all the available sidebar width",page:0,children:[BookChapter(title:"A subsection with a complete title",page:0)]))]
        controller.chapterRevision = controller.visibleRevision
        controller.chapterSource = .embedded
        controller.reloadSidebar()
        for width in [220.0,320.0] {
            controller.split.splitView.setPosition(CGFloat(width),ofDividerAt:0)
            window.contentView?.layoutSubtreeIfNeeded(); controller.fitOutlineColumns()
            XCTAssertEqual(controller.outline.tableColumns.count,2)
            let title = controller.outline.tableColumns[0], page = controller.outline.tableColumns[1]
            XCTAssertEqual(title.width+page.width,controller.sidebarScroll.contentSize.width,accuracy:1)
            XCTAssertEqual(page.width,CGFloat(46),accuracy:0.5)
            XCTAssertGreaterThan(title.width,CGFloat(100))
            XCTAssertEqual(controller.contentsDescription.alignment,.left)
        }
        let node = controller.chapters[0]
        let titleCell = try XCTUnwrap(controller.outlineView(controller.outline,viewFor:controller.outline.tableColumns[0],item:node) as? NSTableCellView)
        let pageCell = try XCTUnwrap(controller.outlineView(controller.outline,viewFor:controller.outline.tableColumns[1],item:node) as? NSTableCellView)
        XCTAssertEqual(titleCell.textField?.stringValue,node.chapter.title)
        XCTAssertEqual(titleCell.toolTip,node.chapter.title)
        XCTAssertEqual(pageCell.textField?.alignment,.right)
    }
    func testNativeAtomicSaveAndReopen() throws {
        let document = PaperDocument(), original = EngineTests.fixture()
        try document.read(from:original,ofType:"com.adobe.pdf")
        XCTAssertEqual(try document.data(ofType:"com.adobe.pdf"),original)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PaperTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder); document.close() }
        let url = folder.appendingPathComponent("Document.pdf")
        try document.writeSafely(to:url,ofType:"com.adobe.pdf",for:.saveOperation)
        document.undoManager?.groupsByEvent = false
        document.undoManager?.beginUndoGrouping()
        document.perform("Rotate") { try $0.rotate(page:0) }
        document.undoManager?.endUndoGrouping()
        try document.writeSafely(to:url,ofType:"com.adobe.pdf",for:.saveOperation)
        let bytes = try Data(contentsOf:url)
        XCTAssertEqual(PDFDocument(data:bytes)?.page(at:0)?.rotation,90)
        XCTAssertThrowsError(try document.writeSafely(to:folder.appendingPathComponent("missing/output.pdf"),ofType:"com.adobe.pdf",for:.saveOperation))
        XCTAssertEqual(try Data(contentsOf:url),bytes)
        let reopened = PaperDocument()
        try reopened.read(from:bytes,ofType:"com.adobe.pdf")
        XCTAssertEqual(try reopened.store.snapshot().data,try document.store.snapshot().data)
        reopened.close(); document.updateChangeCount(.changeCleared)
    }
}
