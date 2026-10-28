// SPDX-License-Identifier: MIT
import AppKit
import PDFKit
import UniformTypeIdentifiers
import PaperCore

final class EditorController: NSViewController, NSToolbarDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    unowned let paper: PaperDocument
    let pdf = CanvasView()
    let sidebar = NSView()
    let inspector = NSStackView()
    let table = NSTableView()
    var sidebarMode = SidebarMode.pages
    let thumbnails = PDFThumbnailView()
    let sidebarBody = NSView()
    var pageIdentityToIndex: [ObjectIdentifier:Int] = [:]
    let filter = NSSearchField()
    let search = NSSearchField()
    let split = NSSplitViewController()
    var sidebarItem: NSSplitViewItem!
    var inspectorItem: NSSplitViewItem!
    let markupScroll = NSScrollView()
    var markupSurface: NSView!
    let documentArea = NSView()
    let pageField = NSTextField(string:"1")
    let pageCountLabel = NSTextField(labelWithString:"")
    var primaryToolGroup: NSToolbarItemGroup?
    let primaryTools: [EditorTool] = [.select,.highlight,.note,.correct]
    var searchToolbarItem: NSSearchToolbarItem?
    var toolButtons: [EditorTool:[NSButton]] = [:]
    let outline = NSOutlineView()
    let sidebarScroll = NSScrollView()
    let contentsDescription = NSTextField(labelWithString:"")
    let emptyContents = NSTextField(wrappingLabelWithString:"")
    var chapters: [ChapterNode] = []
    var visibleChapters: [ChapterNode] = []
    var selectedImage: (page:Int,index:Int,bounds:CGRect)?
    let imageActions = NSStackView()
    var chapterRevision: UInt64?
    var chapterRequest: UInt64?
    var chapterSource = BookContents.Source.unavailable
    let selectionTitle = NSTextField(labelWithString:"No selection")
    let geometryFields = (0..<4).map { _ in NSTextField(string:"") }
    let commentSection = NSStackView()
    let geometrySection = NSStackView()
    let color = NSColorWell()
    let fontPicker = NSPopUpButton()
    let fontSize = NSTextField(string:"14")
    let hint = NSTextField(wrappingLabelWithString:EditorTool.select.hint)
    let status = NSTextField(labelWithString:"")
    let progress = NSProgressIndicator()
    private(set) var visibleRevision: UInt64 = 0
    private var annotationRows: [(page:Int,index:Int,annotation:PDFAnnotation)] = []
    var selectedLink: (page:Int,index:Int,bounds:CGRect)?
    var selectedAnnotation: (page:Int,index:Int)?
    private let comment = NSTextView()
    private var observers: [NSObjectProtocol] = []
    var isRefreshing = false
    var ocrRunning = false
    init(document: PaperDocument) { paper = document; super.init(nibName:nil,bundle:nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        buildSidebar(); buildInspector(); buildMarkupBar()
        let sideController = NSViewController(); sideController.view = sidebar
        let contentController = NSViewController(); contentController.view = makeDocumentArea()
        let inspectorController = NSViewController(); inspectorController.view = inspector
        sidebarItem = NSSplitViewItem(sidebarWithViewController:sideController)
        sidebarItem.minimumThickness = 190; sidebarItem.maximumThickness = 340; sidebarItem.canCollapse = true
        let contentItem = NSSplitViewItem(viewController:contentController)
        contentItem.minimumThickness = 360
        inspectorItem = NSSplitViewItem(viewController:inspectorController)
        inspectorItem.minimumThickness = 240; inspectorItem.maximumThickness = 320; inspectorItem.canCollapse = true; inspectorItem.isCollapsed = true
        split.addSplitViewItem(sidebarItem); split.addSplitViewItem(contentItem); split.addSplitViewItem(inspectorItem)
        split.splitView.dividerStyle = .thin; split.splitView.autosaveName = "PaperSplitViewV2"
        addChild(split)
        split.view.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(split.view)
        NSLayoutConstraint.activate([split.view.topAnchor.constraint(equalTo:view.topAnchor),split.view.bottomAnchor.constraint(equalTo:view.bottomAnchor),split.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),split.view.trailingAnchor.constraint(equalTo:view.trailingAnchor)])
        markupSurface = NativeGlass.surface(content:markupScroll)
        markupSurface.translatesAutoresizingMaskIntoConstraints = false; markupSurface.isHidden = true; markupScroll.isHidden = true
        documentArea.addSubview(markupSurface)
        NSLayoutConstraint.activate([markupSurface.leadingAnchor.constraint(equalTo:documentArea.leadingAnchor,constant:12),markupSurface.trailingAnchor.constraint(equalTo:documentArea.trailingAnchor,constant:-12),markupSurface.topAnchor.constraint(equalTo:documentArea.topAnchor,constant:8),markupSurface.heightAnchor.constraint(equalToConstant:42)])
        pdf.autoScales = true; pdf.displayMode = .singlePageContinuous; pdf.displayDirection = .vertical
        pdf.backgroundColor = .underPageBackgroundColor
        pdf.displaysPageBreaks = true
        pdf.pageBreakMargins = NSEdgeInsets(top:16,left:16,bottom:16,right:16)
        pdf.registerForDraggedTypes([.fileURL])
        pdf.setAccessibilityLabel("PDF document")
        pdf.onGesture = { [weak self] tool,page,bounds,points in self?.gesture(tool,page:page,bounds:bounds,points:points) }
        pdf.onSelection = { [weak self] in self?.markup($0) }
        pdf.onAnnotation = { [weak self] page,a in self?.inspect(page:page,annotation:a) }
        pdf.onFiles = { [weak self] in self?.insert(urls:$0) }
        for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:pdf,queue:.main) { [weak self] _ in self?.updateStatus() })
        }
        observers.append(NotificationCenter.default.addObserver(forName:.PDFThumbnailViewDocumentEdited,object:nil,queue:.main) { [weak self] _ in RunLoop.main.perform(inModes:[.default,.eventTracking]) { self?.commitThumbnailOrder() } })
        do { display(try paper.store.snapshot()) } catch { paper.presentError(error) }
    }
    private func makeDocumentArea() -> NSView {
        let root = documentArea; root.translatesAutoresizingMaskIntoConstraints = false
        pdf.translatesAutoresizingMaskIntoConstraints = false
        pageField.alignment = .center; pageField.isBordered = false; pageField.drawsBackground = false
        pageField.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular)
        pageField.widthAnchor.constraint(equalToConstant:34).isActive = true
        pageField.target = self; pageField.action = #selector(commitPageNumber(_:))
        pageField.setAccessibilityLabel("Page number"); pageField.toolTip = "Go to page (⌥⌘G or ⌘L)"
        pageCountLabel.font = .systemFont(ofSize:11); pageCountLabel.textColor = .secondaryLabelColor
        let pageControl = NSStackView(views:[pageField,pageCountLabel]); pageControl.orientation = .horizontal; pageControl.spacing = 3
        let footer = NSStackView(views:[pageControl,status,NSView(),progress])
        footer.orientation = .horizontal; footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        root.addSubview(pdf); root.addSubview(footer)
        NSLayoutConstraint.activate([pdf.topAnchor.constraint(equalTo:root.topAnchor),pdf.leadingAnchor.constraint(equalTo:root.leadingAnchor),pdf.trailingAnchor.constraint(equalTo:root.trailingAnchor),pdf.bottomAnchor.constraint(equalTo:footer.topAnchor),footer.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:14),footer.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-14),footer.bottomAnchor.constraint(equalTo:root.bottomAnchor),footer.heightAnchor.constraint(equalToConstant:24),root.widthAnchor.constraint(greaterThanOrEqualToConstant:360)])
        return root
    }
    private func buildSidebar() {
        filter.placeholderString = "Filter contents"; filter.target = self; filter.action = #selector(sidebarChanged(_:)); filter.sendsSearchStringImmediately = true
        table.addTableColumn(NSTableColumn(identifier:.init("content")))
        table.headerView = nil; table.delegate = self; table.dataSource = self
        table.style = .sourceList; table.backgroundColor = .clear; table.intercellSpacing = NSSize(width:0,height:6)
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.target = self; table.doubleAction = #selector(sidebarDoubleClick(_:)); table.setAccessibilityLabel("Document sidebar")
        table.registerForDraggedTypes([.init("org.paperpdf.page"),.fileURL]); table.setDraggingSourceOperationMask(.move,forLocal:true)
        let column = NSTableColumn(identifier:.init("chapter")); outline.addTableColumn(column); outline.outlineTableColumn = column
        outline.headerView = nil; outline.style = .sourceList; outline.backgroundColor = .clear
        outline.indentationPerLevel = 14; outline.rowHeight = 32; outline.delegate = self; outline.dataSource = self
        outline.setAccessibilityLabel("Book chapters")
        sidebarScroll.documentView = table; sidebarScroll.hasVerticalScroller = true; sidebarScroll.drawsBackground = false; sidebarScroll.autohidesScrollers = true
        contentsDescription.font = .systemFont(ofSize:11); contentsDescription.textColor = .secondaryLabelColor
        emptyContents.font = .systemFont(ofSize:12); emptyContents.textColor = .secondaryLabelColor; emptyContents.alignment = .center
        thumbnails.pdfView = pdf; thumbnails.backgroundColor = .clear
        thumbnails.maximumNumberOfColumns = 1; thumbnails.thumbnailSize = NSSize(width:140,height:190)
        thumbnails.labelFont = .systemFont(ofSize:12)
        thumbnails.allowsMultipleSelection = true; thumbnails.allowsDragging = true
        thumbnails.setAccessibilityLabel("Page thumbnails")
        for child in [thumbnails,sidebarScroll] {
            child.translatesAutoresizingMaskIntoConstraints = false; sidebarBody.addSubview(child)
            NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo:sidebarBody.leadingAnchor),child.trailingAnchor.constraint(equalTo:sidebarBody.trailingAnchor),child.topAnchor.constraint(equalTo:sidebarBody.topAnchor),child.bottomAnchor.constraint(equalTo:sidebarBody.bottomAnchor)])
        }
        let stack = NSStackView(views:[filter,contentsDescription,sidebarBody]); stack.orientation = .vertical; stack.alignment = .width; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        let material = NSVisualEffectView(); material.material = .sidebar; material.blendingMode = .behindWindow; material.state = .followsWindowActiveState
        material.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(material); sidebar.addSubview(stack)
        emptyContents.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(emptyContents)
        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor),material.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor),material.topAnchor.constraint(equalTo:sidebar.topAnchor),material.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor),
            stack.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:12),stack.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:10),stack.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-10),stack.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor),sidebarBody.heightAnchor.constraint(greaterThanOrEqualToConstant:100),
            emptyContents.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:22),emptyContents.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-22),emptyContents.centerYAnchor.constraint(equalTo:sidebar.centerYAnchor)
        ])
    }
    private func buildInspector() {
        inspector.orientation = .vertical; inspector.alignment = .width; inspector.spacing = 16
        inspector.edgeInsets = NSEdgeInsets(top:18,left:16,bottom:16,right:16)
        selectionTitle.font = .systemFont(ofSize:14,weight:.semibold)
        let introduction = NSTextField(wrappingLabelWithString:"Select an annotation to edit its comment or position.")
        introduction.font = .systemFont(ofSize:12); introduction.textColor = .secondaryLabelColor
        comment.isRichText = false; comment.font = .systemFont(ofSize:13); comment.textContainerInset = NSSize(width:6,height:8)
        comment.setAccessibilityLabel("Comment")
        let scroll = NSScrollView(); scroll.documentView = comment; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant:150).isActive = true
        let save = NSButton(title:"Save",target:self,action:#selector(saveComment(_:))); save.bezelStyle = .rounded
        let delete = NSButton(image:NSImage(systemSymbolName:"trash",accessibilityDescription:"Delete annotation")!,target:self,action:#selector(deleteAnnotation(_:)))
        delete.bezelStyle = .rounded; delete.toolTip = "Delete annotation"
        let actions = NSStackView(views:[delete,NSView(),save]); actions.orientation = .horizontal
        commentSection.orientation = .vertical; commentSection.alignment = .width; commentSection.spacing = 8
        [NSTextField(labelWithString:"Comment"),scroll,actions].forEach(commentSection.addArrangedSubview)
        let labels = ["X","Y","Width","Height"]
        for (label,field) in zip(labels,geometryFields) { field.setAccessibilityLabel(label); field.formatter = Self.dimensionFormatter() }
        let grid = NSGridView(views:[
            [NSTextField(labelWithString:"X"),geometryFields[0],NSTextField(labelWithString:"Y"),geometryFields[1]],
            [NSTextField(labelWithString:"W"),geometryFields[2],NSTextField(labelWithString:"H"),geometryFields[3]]
        ])
        grid.columnSpacing = 6; grid.rowSpacing = 8
        let apply = NSButton(title:"Apply Position",target:self,action:#selector(applyGeometry(_:))); apply.bezelStyle = .rounded
        geometrySection.orientation = .vertical; geometrySection.alignment = .width; geometrySection.spacing = 8
        [NSTextField(labelWithString:"Position & Size"),grid,apply].forEach(geometrySection.addArrangedSubview)
        let replace = NSButton(title:"Replace Image…",target:self,action:#selector(replaceSelectedImage(_:))); replace.bezelStyle = .rounded
        let remove = NSButton(title:"Delete Image",target:self,action:#selector(deleteSelectedImage(_:))); remove.bezelStyle = .rounded
        imageActions.orientation = .vertical; imageActions.alignment = .width; imageActions.spacing = 8
        [replace,remove].forEach(imageActions.addArrangedSubview)
        [selectionTitle,introduction,commentSection,geometrySection,imageActions,NSView()].forEach(inspector.addArrangedSubview)
        commentSection.isHidden = true; geometrySection.isHidden = true; imageActions.isHidden = true
    }
    private static func dimensionFormatter() -> NumberFormatter {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 1; f.minimum = 0; return f
    }
    private func buildMarkupBar() {
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 3; row.edgeInsets = NSEdgeInsets(top:5,left:12,bottom:5,right:12)
        for tool in EditorTool.allCases {
            row.addArrangedSubview(toolButton(tool,compact:true))
            if [.strike,.ink,.signature].contains(tool) { let divider = NSBox(); divider.boxType = .separator; divider.widthAnchor.constraint(equalToConstant:1).isActive = true; divider.heightAnchor.constraint(equalToConstant:18).isActive = true; row.addArrangedSubview(divider) }
        }
        color.color = .systemYellow; color.colorWellStyle = .minimal; color.widthAnchor.constraint(equalToConstant:26).isActive = true; color.heightAnchor.constraint(equalToConstant:24).isActive = true
        color.setAccessibilityLabel("Markup color")
        fontPicker.addItems(withTitles:["Original Font","Helvetica","Times-Roman","Courier"]); fontPicker.controlSize = .small; fontPicker.setAccessibilityLabel("Text font")
        fontSize.controlSize = .small; fontSize.widthAnchor.constraint(equalToConstant:44).isActive = true; fontSize.setAccessibilityLabel("Text size")
        fontPicker.target = self; fontPicker.action = #selector(textStyleChanged(_:)); fontSize.target = self; fontSize.action = #selector(textStyleChanged(_:)); color.target = self; color.action = #selector(textStyleChanged(_:))
        [color,fontPicker,fontSize].forEach(row.addArrangedSubview)
        row.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView(); host.addSubview(row); host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:host.leadingAnchor),row.trailingAnchor.constraint(equalTo:host.trailingAnchor),row.topAnchor.constraint(equalTo:host.topAnchor),row.bottomAnchor.constraint(equalTo:host.bottomAnchor),host.heightAnchor.constraint(equalToConstant:42)])
        markupScroll.documentView = host; markupScroll.hasHorizontalScroller = true; markupScroll.autohidesScrollers = true; markupScroll.drawsBackground = false
        NSLayoutConstraint.activate([host.topAnchor.constraint(equalTo:markupScroll.contentView.topAnchor),host.leadingAnchor.constraint(equalTo:markupScroll.contentView.leadingAnchor)])
        updateToolButtons()
    }
    private func toolButton(_ tool: EditorTool,compact: Bool = false) -> NSButton {
        let button = NSButton(image:NSImage(systemSymbolName:tool.symbol,accessibilityDescription:tool.rawValue) ?? NSImage(),target:self,action:#selector(chooseTool(_:)))
        button.tag = EditorTool.allCases.firstIndex(of:tool)!; button.toolTip = tool.rawValue+" — "+tool.hint
        button.setAccessibilityLabel(tool.rawValue); button.setButtonType(.pushOnPushOff); button.bezelStyle = .texturedRounded
        button.isBordered = !compact; button.imagePosition = .imageOnly
        button.widthAnchor.constraint(equalToConstant:compact ? 28 : 32).isActive = true; button.heightAnchor.constraint(equalToConstant:26).isActive = true
        toolButtons[tool,default:[]].append(button); return button
    }
    func installToolbar(window: NSWindow) {
        let bar = NSToolbar(identifier:"PaperToolbarV3"); bar.delegate = self; bar.allowsUserCustomization = true; bar.autosavesConfiguration = true; bar.displayMode = .iconOnly
        window.toolbar = bar; window.toolbarStyle = .unified
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [id("sidebar"),id("viewMode"),id("zoom"),.flexibleSpace,id("primaryTools"),id("markup"),id("search"),id("inspector")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)+[id("select"),id("highlight"),id("note"),id("correct"),id("signature"),id("text"),id("ocr"),id("rotate"),id("export"),.space]
    }
    private func id(_ value: String) -> NSToolbarItem.Identifier { .init(value) }
    func toolbar(_ toolbar: NSToolbar,itemForItemIdentifier identifier: NSToolbarItem.Identifier,willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier.rawValue == "sidebar" {
            let item = NSMenuToolbarItem(itemIdentifier:identifier)
            configure(item,"Sidebar","sidebar.left",#selector(toggleSidebar(_:)))
            item.menu = makeSidebarMenu(); item.showsIndicator = true; return item
        }
        if identifier.rawValue == "primaryTools" {
            let group = NSToolbarItemGroup(itemIdentifier:identifier,images:primaryTools.map { NSImage(systemSymbolName:$0.symbol,accessibilityDescription:$0.rawValue)! },selectionMode:.selectOne,labels:primaryTools.map(\.rawValue),target:self,action:#selector(choosePrimaryTool(_:)))
            group.label = "Tools"; group.controlRepresentation = .expanded; group.isBordered = true
            primaryToolGroup = group; updateToolButtons(); return group
        }
        if identifier.rawValue == "viewMode" {
            let item = NSMenuToolbarItem(itemIdentifier:identifier); item.menu = makeViewModeMenu(); item.showsIndicator = true
            item.label = "View"; item.toolTip = "Page layout"; item.image = NSImage(systemSymbolName:"rectangle.split.1x2",accessibilityDescription:"View mode"); item.isBordered = true; return item
        }
        if identifier.rawValue == "search" {
            let item = NSSearchToolbarItem(itemIdentifier:identifier)
            search.placeholderString = "Search"; search.target = self; search.action = #selector(searchPDF(_:)); search.setAccessibilityLabel("Search PDF text")
            item.searchField = search; item.preferredWidthForSearchField = 180; item.label = "Search"; searchToolbarItem = item; return item
        }
        let item = NSToolbarItem(itemIdentifier:identifier)
        let tools: [String:EditorTool] = ["select":.select,"highlight":.highlight,"note":.note,"correct":.correct,"signature":.signature,"text":.text]
        if let tool = tools[identifier.rawValue] { configure(item,tool.rawValue,tool.symbol,#selector(chooseToolbarTool(_:))); item.tag = EditorTool.allCases.firstIndex(of:tool)!; return item }
        switch identifier.rawValue {
        case "sidebar": configure(item,"Sidebar","sidebar.left",#selector(toggleSidebar(_:)))
        case "inspector": configure(item,"Inspector","sidebar.right",#selector(toggleInspector(_:)))
        case "markup": configure(item,"Show Markup Toolbar","pencil.tip.crop.circle",#selector(toggleMarkup(_:)))
        case "zoom":
            let control = NSSegmentedControl(images:[NSImage(systemSymbolName:"minus.magnifyingglass",accessibilityDescription:"Zoom out")!,NSImage(systemSymbolName:"plus.magnifyingglass",accessibilityDescription:"Zoom in")!],trackingMode:.momentary,target:self,action:#selector(zoomControl(_:)))
            control.segmentStyle = .separated; item.view = control; item.label = "Zoom"
        case "ocr": configure(item,"Recognize Text","text.viewfinder",#selector(recognizeText(_:)))
        case "rotate": configure(item,"Rotate","rotate.right",#selector(rotatePage(_:)))
        case "export": configure(item,"Export","square.and.arrow.up",#selector(exportDocument(_:)))
        default: return nil
        }
        return item
    }
    private func configure(_ item: NSToolbarItem,_ title: String,_ image: String,_ action: Selector) {
        item.label = title; item.paletteLabel = title; item.toolTip = title; item.image = NSImage(systemSymbolName:image,accessibilityDescription:title); item.target = self; item.action = action; item.isBordered = true
        if item.itemIdentifier.rawValue == "sidebar" { item.isNavigational = true }
    }
    @objc func choosePrimaryTool(_ sender: NSToolbarItemGroup) {
        guard primaryTools.indices.contains(sender.selectedIndex) else { return }; selectTool(primaryTools[sender.selectedIndex])
    }
    @objc func chooseToolbarTool(_ sender: NSToolbarItem) { selectTool(EditorTool.allCases[sender.tag]) }
    @objc func chooseTool(_ sender: NSButton) { selectTool(EditorTool.allCases[sender.tag]) }
    func selectTool(_ tool: EditorTool) {
        pdf.endTextEditing(); pdf.tool = tool
        if [.text,.correct,.ink,.rectangle,.oval,.arrow].contains(tool), color.color == .systemYellow { color.color = .labelColor }
        if tool == .highlight { color.color = .systemYellow }
        if tool != .select { showMarkup() }
        updateToolButtons()
    }
    func updateToolButtons() {
        primaryToolGroup?.selectedIndex = primaryTools.firstIndex(of:pdf.tool) ?? -1
        for (tool,buttons) in toolButtons { for button in buttons { button.state = pdf.tool == tool ? .on : .off; button.contentTintColor = pdf.tool == tool ? .controlAccentColor : .labelColor } }
        fontPicker.isHidden = ![.text,.correct].contains(pdf.tool); fontSize.isHidden = fontPicker.isHidden
    }
    func showMarkup() { markupScroll.isHidden = false; markupSurface?.isHidden = false; pdf.pageBreakMargins.top = 66 }
    @objc func toggleMarkup(_ sender: Any?) { markupScroll.isHidden.toggle(); markupSurface.isHidden = markupScroll.isHidden; pdf.pageBreakMargins.top = markupScroll.isHidden ? 16 : 66 }
    @objc func textStyleChanged(_ sender: Any?) {
        pdf.inlineEditor?.text.textColor = color.color
        if let editor = pdf.inlineEditor { pdf.inlineSize = chosenSize; editor.text.font = .systemFont(ofSize:chosenSize*pdf.scaleFactor) }
    }
    func display(_ revision: PDFRevision) {
        guard revision.number >= visibleRevision else { return }
        guard let document = PDFDocument(data:revision.data) else { paper.presentError(PDFError("PDFKit could not display the committed PDF.")); return }
        isRefreshing = true; defer { isRefreshing = false }
        let oldIndex = currentPageIndex
        let oldScale = pdf.scaleFactor, auto = pdf.autoScales
        let destination = pdf.currentDestination
        let oldPoint = destination?.point
        visibleRevision = revision.number
        // Viewer snapshots are read-only; all form/annotation edits go through
        // native inspector actions and the authoritative command queue.
        for i in 0..<document.pageCount { for a in document.page(at:i)?.annotations ?? [] { a.isReadOnly = true } }
        pdf.endTextEditing()
        pageIdentityToIndex = Dictionary(uniqueKeysWithValues:(0..<document.pageCount).compactMap { index in document.page(at:index).map { (ObjectIdentifier($0),index) } })
        pdf.document = document
        if let page = document.page(at:min(oldIndex,max(0,document.pageCount-1))) {
            if let oldPoint { pdf.go(to:PDFDestination(page:page,at:oldPoint)) } else { pdf.go(to:page) }
        }
        pdf.autoScales = auto; if !auto { pdf.scaleFactor = oldScale }
        selectedAnnotation = nil; selectedLink = nil; selectedImage = nil; comment.string = ""
        selectionTitle.stringValue = "No selection"; commentSection.isHidden = true; geometrySection.isHidden = true; imageActions.isHidden = true
        reloadSidebar(); updateStatus()
    }
    var currentPageIndex: Int { guard let page = pdf.currentPage, let doc = pdf.document else { return 0 }; return doc.index(for:page) }
    var selectedPages: [Int] {
        if sidebarMode == .pages, let pages = thumbnails.selectedPages, !pages.isEmpty, let document = pdf.document {
            return pages.map { document.index(for:$0) }.filter { $0 != NSNotFound }.sorted()
        }
        return [currentPageIndex]
    }
    var rgbColor: UInt32 {
        let c = color.color.usingColorSpace(.sRGB) ?? .black
        return UInt32(c.redComponent*255)<<16 | UInt32(c.greenComponent*255)<<8 | UInt32(c.blueComponent*255)
    }
    var chosenSize: CGFloat { min(500,max(1,CGFloat(fontSize.doubleValue == 0 ? 14 : fontSize.doubleValue))) }
    func index(_ page: PDFPage) -> Int { pdf.document?.index(for:page) ?? 0 }
    func updateStatus() {
        pageField.integerValue = currentPageIndex+1; pageCountLabel.stringValue = "of \(pdf.document?.pageCount ?? 0)"
        status.stringValue = "\(Int(pdf.scaleFactor*100))%" + (paper.store.permitsEditing ? "" : "   ·   Read only")

    }
    @objc func toggleSidebar(_ sender: Any?) { sidebarItem.isCollapsed.toggle() }
    @objc func toggleInspector(_ sender: Any?) { inspectorItem.isCollapsed.toggle() }
    func showInspector() { inspectorItem.isCollapsed = false }
    @objc func zoomControl(_ sender: NSSegmentedControl) { sender.selectedSegment == 0 ? pdf.zoomOut(sender) : pdf.zoomIn(sender) }
    @objc func zoomIn(_ sender: Any?) { pdf.zoomIn(sender) }
    @objc func zoomOut(_ sender: Any?) { pdf.zoomOut(sender) }
    @objc func fitPage(_ sender: Any?) { pdf.autoScales = true }
    @objc func focusSearch(_ sender: Any?) { searchToolbarItem?.beginSearchInteraction() }
    @objc func searchPDF(_ sender: Any?) {
        guard !search.stringValue.isEmpty else { pdf.clearSelection(); return }
        let results = pdf.document?.findString(search.stringValue,withOptions:[.caseInsensitive]) ?? []
        guard let found = results.first else { status.stringValue = "No matches for “\(search.stringValue)”"; return }
        pdf.setCurrentSelection(found,animate:true); pdf.go(to:found)
        status.stringValue = "\(results.count) matches"
    }
    @objc func sidebarChanged(_ sender: Any?) { reloadSidebar() }
    func reloadSidebar() {
        annotationRows = []
        guard let doc = pdf.document else { return }
        let query = filter.stringValue
        for i in 0..<doc.pageCount {
            var engineIndex = 0
            for a in doc.page(at:i)?.annotations ?? [] {
                if a.type == "Widget" || a.type == "Link" || a.type == "Popup" { continue }
                defer { engineIndex += 1 }
                if query.isEmpty || (a.contents ?? "").localizedCaseInsensitiveContains(query) || (a.type ?? "").localizedCaseInsensitiveContains(query) {
                    annotationRows.append((i,engineIndex,a))
                }
            }
        }
        filter.isHidden = sidebarMode.rawValue == 0
        contentsDescription.isHidden = sidebarMode.rawValue != 1
        emptyContents.isHidden = true
        thumbnails.isHidden = sidebarMode != .pages
        sidebarScroll.isHidden = sidebarMode == .pages
        sidebarScroll.documentView = sidebarMode == .outline ? outline : table
        if sidebarMode.rawValue == 1 { loadBookContents() }
        table.rowHeight = sidebarMode.rawValue == 0 ? 100 : 50
        table.reloadData()
    }
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch sidebarMode.rawValue { case 0: return pdf.document?.pageCount ?? 0; case 1: return 0; default: return annotationRows.count }
    }
    func tableView(_ tableView: NSTableView,viewFor tableColumn: NSTableColumn?,row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString:""); label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 2; label.font = .systemFont(ofSize:12); label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label); cell.textField = label
        if sidebarMode.rawValue == 0 {
            let image = NSImageView(); image.image = pdf.document?.page(at:row)?.thumbnail(of:NSSize(width:44,height:62),for:.cropBox); image.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(image); cell.imageView = image
            label.stringValue = "Page \(row+1)"
            NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:12),image.centerYAnchor.constraint(equalTo:cell.centerYAnchor),image.widthAnchor.constraint(equalToConstant:44),image.heightAnchor.constraint(equalToConstant:62),label.leadingAnchor.constraint(equalTo:image.trailingAnchor,constant:12)])
        } else { label.stringValue = "Page \(annotationRows[row].page+1) · \(annotationRows[row].annotation.type ?? "Note")\n\(annotationRows[row].annotation.contents ?? "")"; label.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8).isActive = true }
        NSLayoutConstraint.activate([label.centerYAnchor.constraint(equalTo:cell.centerYAnchor),label.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-8)])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isRefreshing, table.selectedRow >= 0 else { return }
        let row = table.selectedRow
        switch sidebarMode.rawValue {
        case 0: if let page = pdf.document?.page(at:row) { pdf.go(to:page) }
        case 1: break
        default: if row < annotationRows.count { let a = annotationRows[row]; if let page = pdf.document?.page(at:a.page) { pdf.go(to:a.annotation.bounds,on:page); inspect(page:page,annotation:a.annotation) } }
        }
    }
    @objc func sidebarDoubleClick(_ sender: Any?) { if sidebarMode.rawValue == 2 { showInspector() } }
    func tableView(_ tableView: NSTableView,pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard sidebarMode.rawValue == 0 else { return nil }
        let item = NSPasteboardItem(); item.setString("\(row)",forType:.init("org.paperpdf.page")); return item
    }
    func tableView(_ tableView: NSTableView,validateDrop info: NSDraggingInfo,proposedRow row: Int,proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard sidebarMode.rawValue == 0 else { return [] }; tableView.setDropRow(row,dropOperation:.above)
        return info.draggingSource as? NSTableView === table ? .move : .copy
    }
    func tableView(_ tableView: NSTableView,acceptDrop info: NSDraggingInfo,row: Int,dropOperation: NSTableView.DropOperation) -> Bool {
        if info.draggingSource as? NSTableView === table {
            let source = info.draggingPasteboard.pasteboardItems?.compactMap { $0.string(forType:.init("org.paperpdf.page")).flatMap(Int.init) }.sorted() ?? []
            guard !source.isEmpty else { return false }
            var order = Array(0..<(pdf.document?.pageCount ?? 0)).filter { !source.contains($0) }
            let target = max(0,min(order.count,row-source.filter { $0 < row }.count))
            order.insert(contentsOf:source,at:target)
            paper.perform("Reorder Pages") { try $0.reorder(order) }; return true
        }
        let urls = info.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []
        insert(urls:urls,at:row); return !urls.isEmpty
    }
    func outlineRootIndex(row: Int) -> Int? { (outline.item(atRow:outline.selectedRow) as? ChapterNode)?.chapter.embeddedIndex }
    func inspect(page: PDFPage,annotation: PDFAnnotation) {
        selectedImage = nil; imageActions.isHidden = true
        if annotation.type == "Widget" { editField(page:page,annotation:annotation); return }
        if annotation.type == "Link" {
            guard let i = page.annotations.filter({ $0.type == "Link" }).firstIndex(of:annotation) else { return }
            selectedAnnotation = nil
            selectedLink = (index(page),i,PageGeometry(page:page).engineRect(annotation.bounds))
            comment.string = annotation.url?.absoluteString ?? ""
            if let destination = annotation.destination, let p = destination.page { comment.string = "#page=\(index(p)+1)" }
            showSelection(title:"Link",bounds:selectedLink!.bounds,comment:comment.string,geometry:false)
            showInspector(); return
        }
        selectedLink = nil
        let ann = page.annotations.filter { $0.type != "Widget" && $0.type != "Link" && $0.type != "Popup" }
        guard let i = ann.firstIndex(of:annotation) else { return }
        selectedAnnotation = (index(page),i); comment.string = annotation.contents ?? ""
        let editable = ["Text","FreeText","Stamp","Square","Circle"].contains(annotation.type ?? "")
        showSelection(title:annotation.type == "FreeText" ? "Text" : annotation.type ?? "Annotation",bounds:PageGeometry(page:page).engineRect(annotation.bounds),comment:comment.string,geometry:editable)
        showInspector()
        if annotation.type == "FreeText" {
            beginAnnotationTextEditing(page:page,annotation:annotation,index:i)
        }
    }
    @objc func saveComment(_ sender: Any?) {
        if let link = selectedLink {
            let uri = comment.string
            guard validLink(uri) else { return }
            paper.perform("Edit Link") { try $0.editLink(page:link.page,index:link.index,bounds:link.bounds,uri:uri) }; return
        }
        guard let selectedAnnotation else { return }
        let contents = comment.string
        paper.perform("Edit Comment") { try $0.annotation(page:selectedAnnotation.page,index:selectedAnnotation.index,contents:contents) }
    }
    @objc func deleteAnnotation(_ sender: Any?) {
        if let link = selectedLink {
            paper.perform("Delete Link") { try $0.editLink(page:link.page,index:link.index,bounds:link.bounds,uri:"",remove:true) }; return
        }
        guard let a = selectedAnnotation else { return }
        paper.perform("Delete Annotation") { try $0.annotation(page:a.page,index:a.index,remove:true) }
    }
    @objc func transformAnnotation(_ sender: Any?) { showInspector() }
    func showSelection(title: String,bounds: CGRect,comment value: String,geometry: Bool) {
        selectionTitle.stringValue = title; comment.string = value
        commentSection.isHidden = false; geometrySection.isHidden = !geometry
        for (field,value) in zip(geometryFields,[bounds.minX,bounds.minY,bounds.width,bounds.height]) { field.doubleValue = Double(value) }
    }
    @objc func applyGeometry(_ sender: Any?) {
        let v = geometryFields.map(\.doubleValue)
        guard v.allSatisfy(\.isFinite), v[2]>0, v[3]>0 else { return }
        let bounds = CGRect(x:v[0],y:v[1],width:v[2],height:v[3])
        if let image = selectedImage {
            paper.perform("Move / Resize Image") { try $0.editImage(page:image.page,index:image.index,bounds:bounds) }; return
        }
        guard let selectedAnnotation else { return }
        paper.perform("Move / Resize Annotation") { try $0.transformAnnotation(page:selectedAnnotation.page,index:selectedAnnotation.index,bounds:CGRect(x:v[0],y:v[1],width:v[2],height:v[3])) }
    }
}
