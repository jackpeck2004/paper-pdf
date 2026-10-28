// SPDX-License-Identifier: MIT
import AppKit

final class PaperDocumentController: NSDocumentController {
    override var defaultType: String? { "com.adobe.pdf" }
    override func documentClass(forType typeName: String) -> AnyClass? { PaperDocument.self }
    override func typeForContents(of url: URL) throws -> String { "com.adobe.pdf" }
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument { PaperDocument() }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let documents = PaperDocumentController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func showProject(_ sender: Any?) {
        let credits = NSAttributedString(string:"Paper original source: MIT\nIncludes MuPDF under AGPL v3.\nAll document processing stays on your Mac.",attributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options:[
            .applicationName:"Paper",
            .applicationVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.2.3",
            .version:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "5",
            .credits:credits
        ])
    }
}
func makeMenu(_ name: String, parent: NSMenu) -> NSMenu {
    let item = NSMenuItem(title:name,action:nil,keyEquivalent:"")
    let menu = NSMenu(title:name); item.submenu = menu; parent.addItem(item); return menu
}
func item(_ menu: NSMenu,_ title: String,_ action: Selector,_ key: String = "",_ mods: NSEvent.ModifierFlags = [.command]) {
    let i = NSMenuItem(title:title,action:action,keyEquivalent:key); i.keyEquivalentModifierMask = mods; menu.addItem(i)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
let main = NSMenu()
let application = makeMenu("Paper",parent:main)
item(application,"About Paper",#selector(AppDelegate.showProject(_:)))
application.addItem(.separator())
item(application,"Hide Paper",#selector(NSApplication.hide(_:)),"h")
item(application,"Hide Others",#selector(NSApplication.hideOtherApplications(_:)),"h",[.command,.option])
application.addItem(.separator())
item(application,"Quit Paper",#selector(NSApplication.terminate(_:)),"q")
let file = makeMenu("File",parent:main)
item(file,"New",#selector(NSDocumentController.newDocument(_:)),"n")
item(file,"Open…",#selector(NSDocumentController.openDocument(_:)),"o")
let recent = makeMenu("Open Recent",parent:file)
recent.perform(NSSelectorFromString("_setMenuName:"),with:"NSRecentDocumentsMenu")
item(recent,"Clear Menu",#selector(NSDocumentController.clearRecentDocuments(_:)))
file.addItem(.separator())
item(file,"Close",#selector(NSWindow.performClose(_:)),"w")
item(file,"Save",#selector(NSDocument.save(_:)),"s")
item(file,"Save As…",#selector(NSDocument.saveAs(_:)),"s",[.command,.shift])
item(file,"Revert to Saved…",#selector(NSDocument.revertToSaved(_:)))
file.addItem(.separator())
item(file,"Export…",#selector(EditorController.exportDocument(_:)),"e",[.command,.shift])
item(file,"Share…",#selector(EditorController.shareDocument(_:)))
item(file,"Print…",#selector(EditorController.printPDF(_:)),"p")
let edit = makeMenu("Edit",parent:main)
item(edit,"Undo",Selector(("undo:")),"z")
item(edit,"Redo",Selector(("redo:")),"z",[.command,.shift])
edit.addItem(.separator())
item(edit,"Cut",#selector(NSText.cut(_:)),"x")
item(edit,"Copy",#selector(NSText.copy(_:)),"c")
item(edit,"Paste",#selector(NSText.paste(_:)),"v")
item(edit,"Select All",#selector(NSText.selectAll(_:)),"a")
item(edit,"Find…",#selector(EditorController.focusSearch(_:)),"f")
item(edit,"Delete Selected Annotation",#selector(EditorController.deleteAnnotation(_:)))
let tools = makeMenu("Tools",parent:main)
item(tools,"Highlight Selection",#selector(EditorController.highlight(_:)),"h",[.command,.shift])
item(tools,"Comment on Selection…",#selector(EditorController.commentSelection(_:)),"k",[.command,.option])
item(tools,"Correct Selected Text…",#selector(EditorController.correctSelection(_:)),"t",[.command,.option])
item(tools,"Recognize Text on Current Page",#selector(EditorController.recognizeText(_:)))
item(tools,"Fill Form Field…",#selector(EditorController.fillForm(_:)))
item(tools,"Add Bookmark…",#selector(EditorController.addBookmark(_:)))
item(tools,"Remove Selected Bookmark",#selector(EditorController.removeBookmark(_:)))
let pages = makeMenu("Pages",parent:main)
item(pages,"Insert PDF or Images…",#selector(EditorController.insertFiles(_:)))
item(pages,"Insert Blank Page",#selector(EditorController.insertBlank(_:)))
item(pages,"Extract Selected Pages…",#selector(EditorController.extractPages(_:)))
item(pages,"Duplicate Selected Pages",#selector(EditorController.duplicatePages(_:)))
item(pages,"Delete Selected Pages",#selector(EditorController.deletePages(_:)))
item(pages,"Rotate Right",#selector(EditorController.rotatePage(_:)),"r",[.command,.option])
item(pages,"Move Page Earlier",#selector(EditorController.moveEarlier(_:)))
item(pages,"Move Page Later",#selector(EditorController.moveLater(_:)))
let go = makeMenu("Go",parent:main)
readerGoMenuItems(target:nil).forEach(go.addItem)
let view = makeMenu("View",parent:main)
readerViewMenuItems(target:nil).forEach(view.addItem)
view.addItem(.separator())
item(view,"Toggle Sidebar",#selector(EditorController.toggleSidebar(_:)),"1",[.command,.option])
item(view,"Show Markup Toolbar",#selector(EditorController.toggleMarkup(_:)),"a",[.command,.shift])
item(view,"Toggle Inspector",#selector(EditorController.toggleInspector(_:)),"2",[.command,.option])
item(view,"Zoom In",#selector(EditorController.zoomIn(_:)),"+")
item(view,"Zoom Out",#selector(EditorController.zoomOut(_:)),"-")
item(view,"Fit to Page",#selector(EditorController.fitPage(_:)),"0")
item(view,"Enter Full Screen",#selector(NSWindow.toggleFullScreen(_:)),"f",[.command,.control])
let window = makeMenu("Window",parent:main)
item(window,"Minimize",#selector(NSWindow.performMiniaturize(_:)),"m")
item(window,"Zoom",#selector(NSWindow.performZoom(_:)))
item(window,"Show Next Tab",NSSelectorFromString("selectNextTab:"),"}")
item(window,"Show Previous Tab",NSSelectorFromString("selectPreviousTab:"),"{")
item(window,"Merge All Windows",NSSelectorFromString("mergeAllWindows:"))
app.windowsMenu = window
app.mainMenu = main
app.run()
