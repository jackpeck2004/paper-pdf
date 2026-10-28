// SPDX-License-Identifier: MIT
import AppKit
import PDFKit
import UniformTypeIdentifiers
import PaperCore

extension EditorController {
    func alert(_ title: String,_ message: String) { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.runModal() }
    func prompt(_ title: String, message: String = "", value: String = "", multiline: Bool = false) -> String? {
        let a = NSAlert(); a.messageText = title; a.informativeText = message
        a.addButton(withTitle:"Apply"); a.addButton(withTitle:"Cancel")
        if multiline {
            let text = NSTextView(frame:NSRect(x:0,y:0,width:360,height:130)); text.isRichText = false; text.font = .systemFont(ofSize:13); text.string = value
            let scroll = NSScrollView(frame:text.frame); scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            a.accessoryView = scroll; a.window.initialFirstResponder = text
            return a.runModal() == .alertFirstButtonReturn ? text.string : nil
        }
        let text = NSTextField(string:value); text.frame = NSRect(x:0,y:0,width:360,height:24); a.accessoryView = text; a.window.initialFirstResponder = text
        return a.runModal() == .alertFirstButtonReturn ? text.stringValue : nil
    }
    @objc func highlight(_ sender: Any?) { markup(.highlight) }
    @objc func commentSelection(_ sender: Any?) {
        guard let selection = pdf.currentSelection, let page = selection.pages.first else { return }
        let bounds = selection.bounds(for:page), revision = visibleRevision
        pdf.beginTextEditing(on:page,bounds:bounds,value:"",size:13,color:.labelColor,multiline:true) { [weak self] value in
            guard let self, self.visibleRevision == revision else { return }
            self.markup(.highlight,contents:value)
        }
    }
    func markup(_ tool: EditorTool,contents: String = "") {
        guard let selection = pdf.currentSelection, let kind = tool.annotationKind else { return }
        let selections = selection.selectionsByLine()
        let data = selection.pages.map { page -> (Int,[CGRect]) in
            let g = PageGeometry(page:page)
            return (index(page),selections.filter { $0.pages.contains(page) }.map { g.engineRect($0.bounds(for:page)) }.filter { !$0.isEmpty })
        }.filter { !$0.1.isEmpty }
        guard !data.isEmpty else { return }
        let color = rgbColor
        paper.perform(contents.isEmpty ? tool.rawValue : "Add Comment") { engine in
            for (page,quads) in data {
                let bounds = quads.reduce(CGRect.null) { $0.union($1) }
                try engine.annotate(page:page,kind:kind,bounds:bounds,quads:quads,contents:contents,color:color)
            }
        }
    }
    func gesture(_ tool: EditorTool,page: PDFPage,bounds: CGRect,points: [CGPoint]) {
        let pageIndex = index(page), g = PageGeometry(page:page)
        let clipped = bounds.intersection(page.bounds(for:.cropBox))
        let r = g.engineRect(clipped.isNull ? bounds : clipped)
        let color = rgbColor, size = chosenSize
        switch tool {
        case .editImage: editImage(page:page,at:g.enginePoint(bounds.origin))
        case .correct: correct(page:page,at:g.enginePoint(bounds.origin))
        case .form:
            if let a = page.annotations.first(where: { $0.type == "Widget" && $0.bounds.contains(bounds.origin) }) { editField(page:page,annotation:a) }
            else { alert("No Form Field", "Click an existing form field. Use Text Box for a non-interactive form.") }
        case .note:
            let position = g.enginePoint(bounds.origin)
            let noteBounds = CGRect(x:position.x,y:position.y,width:24,height:24)
            let revision = visibleRevision
            pdf.beginTextEditing(on:page,bounds:CGRect(origin:bounds.origin,size:CGSize(width:220,height:80)),value:"",size:13,color:.labelColor,multiline:true) { [weak self] value in
                self?.paper.perform("Add Note",expectedRevision:revision) { try $0.annotate(page:pageIndex,kind:"Text",bounds:noteBounds,contents:value,color:color) }
            }
        case .text:
            let revision = visibleRevision
            pdf.beginTextEditing(on:page,bounds:bounds,value:"",size:size,color:self.color.color,multiline:true) { [weak self] value in
                guard let self else { return }
                self.paper.perform("Add Text",expectedRevision:revision) { try $0.annotate(page:pageIndex,kind:"FreeText",bounds:r,contents:value,color:self.rgbColor,size:self.chosenSize) }
            }
        case .image: placeImage(page:pageIndex,bounds:r)
        case .signature: placeSignature(page:pageIndex,bounds:r)
        case .crop: paper.perform("Crop Page") { try $0.crop(page:pageIndex,bounds:r) }
        case .redact:
            let a = NSAlert(); a.messageText = "Remove content in this area?"; a.informativeText = "Text, images, and graphics touching the area will be removed. Overlapping images may be removed entirely. You can undo before closing; saved output contains no earlier PDF revisions."
            a.addButton(withTitle:"Redact"); a.addButton(withTitle:"Cancel")
            if a.runModal() == .alertFirstButtonReturn { paper.perform("Redact") { try $0.redact(page:pageIndex,bounds:r) } }
        case .link:
            guard let uri = prompt("Add Link",message:"Enter https://… or #page=2",value:"https://"), validLink(uri) else { return }
            paper.perform("Add Link") { try $0.link(page:pageIndex,bounds:r,uri:uri) }
        case .ink:
            let trail = points.map(g.enginePoint)
            paper.perform("Draw") { try $0.annotate(page:pageIndex,kind:"Ink",bounds:r,color:color,points:trail) }
        default:
            if let kind = tool.annotationKind { paper.perform(tool.rawValue) { try $0.annotate(page:pageIndex,kind:kind,bounds:r,color:color,size:size,points:points.map(g.enginePoint)) } }
        }
    }
    func validLink(_ uri: String) -> Bool {
        if uri.hasPrefix("#page="), let n = Int(uri.dropFirst(6)), n > 0, n <= (pdf.document?.pageCount ?? 0) { return true }
        if let u = URL(string:uri), ["https","http","mailto"].contains(u.scheme?.lowercased() ?? "") { return true }
        alert("Unsupported Link", "Use an HTTP, HTTPS, or mailto URL, or a valid #page= destination."); return false
    }
    @objc func correctSelection(_ sender: Any?) {
        guard let s = pdf.currentSelection, let page = s.pages.first else { alert("Select Text", "Select text or choose Correct Text and click a line."); return }
        let r = PageGeometry(page:page).engineRect(s.bounds(for:page))
        correct(page:page,at:CGPoint(x:r.midX,y:r.midY))
    }
    func correct(page: PDFPage,at point: CGPoint) {
        do {
            let pageIndex = index(page)
            let lines = try paper.store.read { try $0.lines(page:pageIndex) }
            guard let line = lines.first(where: { $0.bounds.insetBy(dx:-2,dy:-2).contains(point) }) else {
                alert("No Editable Text", "This area has no text layer. OCR makes scans searchable; it does not turn scanned pixels into editable text."); return
            }
            guard line.editable else { throw PDFError("This line has mixed styles or complex text. Local corrections currently require a horizontal line with one font, size, and color.") }
            selectTool(.correct)
            fontSize.doubleValue = Double(line.size)
            color.color = NSColor(srgbRed:CGFloat((line.color>>16)&255)/255,green:CGFloat((line.color>>8)&255)/255,blue:CGFloat(line.color&255)/255,alpha:1)
            fontPicker.selectItem(at:0)
            let revision = visibleRevision
            let pdfBounds = PageGeometry(page:page).pdfRect(line.bounds)
            showMarkup()
            pdf.beginTextEditing(on:page,bounds:pdfBounds,value:line.text,size:line.size,color:color.color,multiline:false) { [weak self] value in
                guard let self else { return }
                let font = self.fontPicker.indexOfSelectedItem == 0 ? "" : self.fontPicker.titleOfSelectedItem ?? ""
                self.paper.perform("Correct Text",expectedRevision:revision) { try $0.replaceLine(page:pageIndex,index:line.index,text:value,font:font,size:self.chosenSize,color:self.rgbColor) }
            }
        } catch { paper.presentError(error) }
    }
    func editField(page: PDFPage,annotation: PDFAnnotation) {
        let widgets = page.annotations.filter { $0.type == "Widget" }
        guard let i = widgets.firstIndex(of:annotation) else { return }
        let p = index(page), revision = visibleRevision
        if annotation.widgetFieldType == .button {
            let value = annotation.buttonWidgetState.rawValue == 1 ? "Off" : annotation.buttonWidgetStateString
            paper.perform("Fill Form",expectedRevision:revision) { try $0.form(page:p,index:i,value:value) }
        } else {
            pdf.beginTextEditing(on:page,bounds:annotation.bounds,value:annotation.widgetStringValue ?? "",size:annotation.font?.pointSize ?? 13,color:.labelColor,multiline:annotation.isMultiline) { [weak self] value in
                self?.paper.perform("Fill Form",expectedRevision:revision) { try $0.form(page:p,index:i,value:value) }
            }
        }
    }
    @objc func fillForm(_ sender: Any?) {
        guard let page = pdf.currentPage else { return }
        let fields = page.annotations.filter { $0.type == "Widget" }
        guard !fields.isEmpty else { alert("No Form Fields", "Use Text Box to fill a non-interactive form."); return }
        let a = NSAlert(); a.messageText = "Choose a Form Field"; a.addButton(withTitle:"Edit"); a.addButton(withTitle:"Cancel")
        let picker = NSPopUpButton(frame:NSRect(x:0,y:0,width:320,height:28)); picker.addItems(withTitles:fields.enumerated().map { "\($0.offset+1). \($0.element.fieldName ?? "Field")" }); a.accessoryView = picker
        if a.runModal() == .alertFirstButtonReturn { editField(page:page,annotation:fields[picker.indexOfSelectedItem]) }
    }
    @objc func recognizeText(_ sender: Any?) {
        guard !ocrRunning else { return }
        do {
            let snapshot = try paper.store.snapshot(), pages = selectedPages
            ocrRunning = true; progress.startAnimation(nil); status.stringValue = "Recognizing text on device…"
            DispatchQueue.global(qos:.userInitiated).async { [weak self] in
                let result = Result { try OCRService.recognize(data:snapshot.data,pages:pages) }
                DispatchQueue.main.async {
                    guard let self else { return }; self.ocrRunning = false; self.progress.stopAnimation(nil)
                    switch result {
                    case .success(let lines):
                        guard !lines.isEmpty else { self.alert("No New Text", "Selected pages already have text, or no text was recognized."); self.updateStatus(); return }
                        self.paper.perform("Recognize Text",expectedRevision:snapshot.number) { engine in for l in lines { try engine.ocr(page:l.page,bounds:l.bounds,text:l.text) } }
                    case .failure(let error): self.paper.presentError(error)
                    }
                }
            }
        } catch { paper.presentError(error) }
    }
    @objc func rotatePage(_ sender: Any?) { let pages = selectedPages; paper.perform("Rotate Pages") { e in for p in pages { try e.rotate(page:p) } } }
    @objc func insertBlank(_ sender: Any?) { let at = currentPageIndex+1; paper.perform("Insert Blank Page") { try $0.insertBlank(at:at) } }
    @objc func deletePages(_ sender: Any?) {
        let selected = Set(selectedPages), count = pdf.document?.pageCount ?? 0
        let keep = Array(0..<count).filter { !selected.contains($0) }
        guard !keep.isEmpty else { alert("Keep One Page", "A PDF must contain at least one page."); return }
        paper.perform("Delete Pages") { try $0.reorder(keep) }
    }
    @objc func duplicatePages(_ sender: Any?) {
        let pages = selectedPages
        paper.perform("Duplicate Pages") { try $0.duplicate(pages:pages) }
    }
    @objc func moveEarlier(_ sender: Any?) { movePage(delta:-1) }
    @objc func moveLater(_ sender: Any?) { movePage(delta:1) }
    private func movePage(delta: Int) {
        var order = Array(0..<(pdf.document?.pageCount ?? 0)); let p = currentPageIndex, other = p+delta
        guard order.indices.contains(other) else { return }; order.swapAt(p,other)
        paper.perform("Move Page") { try $0.reorder(order) }
        if let page = pdf.document?.page(at:other) { pdf.go(to:page) }
    }
    @objc func insertFiles(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.allowedContentTypes = [.pdf,.png,.jpeg,.tiff,.heic]
        if panel.runModal() == .OK { insert(urls:panel.urls) }
    }
    func insert(urls: [URL],at position: Int? = nil) {
        guard !urls.isEmpty else { return }
        do {
            let documents = try urls.map { url -> Data in
                if url.pathExtension.lowercased() == "pdf" { return try Data(contentsOf:url) }
                guard let image = NSImage(contentsOf:url), let page = PDFPage(image:image), let data = page.dataRepresentation else { throw PDFError("Could not read \(url.lastPathComponent).") }
                let doc = PDFDocument(); doc.insert(page,at:0)
                guard let pdfData = doc.dataRepresentation() else { throw PDFError("Could not convert image to PDF.") }
                _ = data
                return pdfData
            }
            let start = position ?? currentPageIndex+1
            paper.perform("Insert Pages") { engine in
                var at = start
                for data in documents { let count = try PDFEngine(data:data).pageCount; try engine.insert(data:data,at:at); at += count }
            }
        } catch { paper.presentError(error) }
    }
    @objc func extractPages(_ sender: Any?) {
        do {
            let pages = selectedPages
            let data = try paper.store.read { try $0.extract(pages:pages) }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "Extracted Pages.pdf"
            if panel.runModal() == .OK, let url = panel.url { try data.write(to:url,options:.atomic) }
        } catch { paper.presentError(error) }
    }
    @objc func addBookmark(_ sender: Any?) {
        guard let title = prompt("Add Bookmark",value:"Page \(currentPageIndex+1)"), !title.isEmpty else { return }
        let page = currentPageIndex; paper.perform("Add Bookmark") { try $0.bookmark(page:page,title:title) }
    }
    @objc func removeBookmark(_ sender: Any?) {
        guard sidebarMode.rawValue == 1, outline.selectedRow >= 0 else { return }
        // Nested bookmarks are preserved; this first release manages root entries.
        guard let root = selectedRootBookmark() else { alert("Select a Top-Level Bookmark", "Nested bookmarks are preserved. Select a top-level entry to remove its subtree."); return }
        paper.perform("Remove Bookmark") { try $0.bookmark(page:0,removeIndex:root) }
    }
    func selectedRootBookmark() -> Int? { outlineRootIndex(row:table.selectedRow) }
    func editImage(page: PDFPage, at point: CGPoint) {
        do {
            let pageIndex = index(page)
            guard let image = try paper.store.read({ try $0.images(page:pageIndex) }).reversed().first(where: { $0.bounds.contains(point) }) else { throw PDFError("No image was found here. Placed images and signatures can be selected with the Select tool.") }
            guard image.editable else { throw PDFError("This image is rotated or masked and cannot be safely edited.") }
            selectedAnnotation = nil; selectedLink = nil
            selectedImage = (pageIndex,image.index,image.bounds)
            showSelection(title:"Image",bounds:image.bounds,comment:"",geometry:true)
            commentSection.isHidden = true; imageActions.isHidden = false
            showInspector()
        } catch { paper.presentError(error) }
    }
    @objc func replaceSelectedImage(_ sender: Any?) {
        guard let image = selectedImage else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.tiff,.heic]
        guard panel.runModal() == .OK, let url = panel.url, let selected = NSImage(contentsOf:url), let tiff = selected.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let data = bitmap.representation(using:.png,properties:[:]) else { return }
        paper.perform("Replace Image") { try $0.editImage(page:image.page,index:image.index,bounds:image.bounds,replacement:data) }
    }
    @objc func deleteSelectedImage(_ sender: Any?) {
        guard let image = selectedImage else { return }
        paper.perform("Delete Image") { try $0.editImage(page:image.page,index:image.index,bounds:image.bounds,remove:true) }
    }
    func placeImage(page: Int,bounds: CGRect) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg,.tiff,.heic]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let image = NSImage(contentsOf:url), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff), let data = rep.representation(using:.png,properties:[:]) else { throw PDFError("Could not decode the image.") }
            paper.perform("Place Image") { try $0.image(page:page,bounds:bounds,data:data) }
        } catch { paper.presentError(error) }
    }
    func placeSignature(page: Int,bounds: CGRect) {
        guard let data = SignaturePanel.choose() else { return }
        paper.perform("Place Signature") { try $0.image(page:page,bounds:bounds,data:data) }
    }
    func transformSelectedAnnotation() { showInspector() }
    func beginAnnotationTextEditing(page: PDFPage,annotation: PDFAnnotation,index annotationIndex: Int) {
        let pageIndex = index(page), revision = visibleRevision
        pdf.beginTextEditing(on:page,bounds:annotation.bounds,value:annotation.contents ?? "",size:annotation.font?.pointSize ?? 14,color:annotation.fontColor ?? .labelColor,multiline:true) { [weak self] value in
            self?.paper.perform("Edit Text",expectedRevision:revision) { try $0.annotation(page:pageIndex,index:annotationIndex,contents:value) }
        }
    }
    @objc func exportDocument(_ sender: Any?) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(paper.displayName.replacingOccurrences(of:".pdf",with:"")) Copy.pdf"; panel.allowedContentTypes = [.pdf,.png,.plainText]
        let format = NSPopUpButton(); format.addItems(withTitles:["PDF · editable annotations","PDF · flattened annotations and forms","PDF · compressed, images at 150 dpi","PNG · current page","Text · annotation summary"])
        let password = NSSecureTextField(); password.placeholderString = "Optional password for PDF output"
        let stack = NSStackView(views:[NSTextField(labelWithString:"Export format"),format,password]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8; stack.frame = NSRect(x:0,y:0,width:370,height:100); password.widthAnchor.constraint(equalToConstant:370).isActive = true; panel.accessoryView = stack
        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }
        do {
            let selected = format.indexOfSelectedItem
            let ext = selected == 3 ? "png" : selected == 4 ? "txt" : "pdf"
            let url = chosenURL.pathExtension.lowercased() == ext ? chosenURL : chosenURL.deletingPathExtension().appendingPathExtension(ext)
            if url != chosenURL && FileManager.default.fileExists(atPath:url.path) {
                let a = NSAlert(); a.messageText = "Replace \(url.lastPathComponent)?"; a.addButton(withTitle:"Replace"); a.addButton(withTitle:"Cancel"); guard a.runModal() == .alertFirstButtonReturn else { return }
            }
            let data: Data
            switch selected {
            case 3:
                guard let page = pdf.currentPage else { return }
                let b = page.bounds(for:.cropBox), image = page.thumbnail(of:NSSize(width:b.width*2,height:b.height*2),for:.cropBox)
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) else { throw PDFError("Could not render this page.") }; data = png
            case 4:
                var lines: [String] = []
                if let doc = pdf.document { for p in 0..<doc.pageCount { for a in doc.page(at:p)?.annotations ?? [] where a.type != "Widget" && a.type != "Link" { lines.append("Page \(p+1) — \(a.type ?? "Annotation")\n\(a.contents ?? "")\n") } } }
                data = Data(lines.joined(separator:"\n").utf8)
            default: data = try paper.store.read { try $0.export(password:password.stringValue,flatten:selected == 1,compress:selected == 2) }
            }
            try data.write(to:url,options:.atomic)
        } catch { paper.presentError(error) }
    }
    @objc func printPDF(_ sender: Any?) {
        guard let op = pdf.document?.printOperation(for:paper.printInfo,scalingMode:.pageScaleDownToFit,autoRotate:true) else { return }
        op.run()
    }
    @objc func shareDocument(_ sender: Any?) {
        paper.save(withDelegate:self,didSave:#selector(didSaveForSharing(_:didSave:contextInfo:)),contextInfo:nil)
    }
    @objc func didSaveForSharing(_ document: NSDocument,didSave: Bool,contextInfo: UnsafeMutableRawPointer?) {
        guard didSave, let url = document.fileURL else { return }
        let picker = NSSharingServicePicker(items:[url]); picker.show(relativeTo:search.bounds,of:search,preferredEdge:.minY)
    }
}
