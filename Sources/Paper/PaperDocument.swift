// SPDX-License-Identifier: MIT
import AppKit
import PDFKit
import PaperCore

final class PaperDocument: NSDocument {
    var store: DocumentStore!
    private var originalData: Data?
    private var savePassword = ""
    private var acceptedSignatureWarning = false
    override init() {
        super.init()
        do { store = try DocumentStore() } catch { NSApplication.shared.presentError(error) }
        hasUndoManager = true
    }
    override class var autosavesInPlace: Bool { true }
    override func makeWindowControllers() {
        let controller = EditorController(document:self)
        let window = NSWindow(contentViewController:controller)
        window.setContentSize(NSSize(width:1120,height:800))
        window.minSize = NSSize(width:820,height:560)
        window.title = displayName
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.tabbingMode = .preferred
        window.setFrameAutosaveName("PaperDocumentWindowV2")
        let wc = NSWindowController(window:window)
        addWindowController(wc)
        controller.installToolbar(window:window)
        window.center()
    }
    override func read(from data: Data, ofType typeName: String) throws {
        do { store = try DocumentStore(data:data); savePassword = "" }
        catch {
            guard error.localizedDescription.localizedCaseInsensitiveContains("password") else { throw error }
            var opened: DocumentStore?
            while opened == nil {
                let alert = NSAlert()
                alert.messageText = "Unlock PDF"
                alert.informativeText = "Enter the PDF password. Saved changes will use this password."
                let field = NSSecureTextField(frame:NSRect(x:0,y:0,width:300,height:24))
                alert.accessoryView = field
                alert.addButton(withTitle:"Unlock"); alert.addButton(withTitle:"Cancel")
                alert.window.initialFirstResponder = field
                guard alert.runModal() == .alertFirstButtonReturn else { throw CocoaError(.userCancelled) }
                do { opened = try DocumentStore(data:data,password:field.stringValue); savePassword = field.stringValue }
                catch { NSApplication.shared.presentError(error) }
            }
            store = opened
        }
        originalData = data
        acceptedSignatureWarning = false
    }
    override func data(ofType typeName: String) throws -> Data {
        if store.currentRevision == 0, let originalData { return originalData }
        return try store.read { try $0.export(password:savePassword) }
    }
    func perform(_ name: String, expectedRevision: UInt64? = nil, _ action: (PDFEngine) throws -> Void) {
        do {
            guard authorizeSignedEdit() else { return }
            let change = try store.transact(expectedRevision:expectedRevision,action)
            registerRestore(change.before,name:name)
            updateChangeCount(.changeDone)
            refresh(change.after)
        } catch { presentError(error) }
    }
    private func authorizeSignedEdit() -> Bool {
        guard store.originallySigned && !acceptedSignatureWarning else { return true }
        let alert = NSAlert()
        alert.messageText = "Edit an unsigned copy?"
        alert.informativeText = "Editing invalidates certificate signatures. Paper will require a new save location, keeping the original file intact. Visual signatures are not certificates."
        alert.addButton(withTitle:"Edit a Copy"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        acceptedSignatureWarning = true
        fileURL = nil
        return true
    }
    private func registerRestore(_ data: Data, name: String) {
        undoManager?.registerUndo(withTarget:self) { target in
            do {
                let inverse = try target.store.snapshot().data
                let restored = try target.store.restore(data)
                target.registerRestore(inverse,name:name)
                target.refresh(restored)
            } catch { target.presentError(error) }
        }
        undoManager?.setActionName(name)
    }
    func refresh(_ revision: PDFRevision) {
        for wc in windowControllers {
            (wc.contentViewController as? EditorController)?.display(revision)
        }
    }
}
