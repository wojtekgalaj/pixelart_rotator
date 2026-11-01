import AppKit

func trace(_ message: String) {
    let line = message + "\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/pixel-rotator/trace.txt")
    if FileManager.default.fileExists(atPath: url.path),
       let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

@main
enum PixelRotatorMain {
    /// A bare executable has no Info.plist, so NSApplicationMain never creates
    /// the delegate. `run()` does not return, which keeps the delegate alive
    /// (`NSApplication.delegate` is a weak reference).
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MainWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Pixel Rotator", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Pixel Rotator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let spriteItem = NSMenuItem()
        main.addItem(spriteItem)
        let sprite = NSMenu(title: "Sprite")
        sprite.addItem(withTitle: "Load Demo Taxi", action: #selector(MainWindowController.loadDemo(_:)), keyEquivalent: "d")
        sprite.addItem(withTitle: "Clear Views", action: #selector(MainWindowController.clearAll(_:)), keyEquivalent: "")
        sprite.addItem(.separator())
        sprite.addItem(withTitle: "Export Sprite Sheet…", action: #selector(MainWindowController.exportSheet(_:)), keyEquivalent: "e")
        sprite.addItem(withTitle: "Export GIF…", action: #selector(MainWindowController.exportGIF(_:)), keyEquivalent: "g")
        spriteItem.submenu = sprite

        NSApp.mainMenu = main
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController()
        self.controller = controller
        trace("did finish launching env \(ProcessInfo.processInfo.environment["PIXEL_ROTATOR_SNAPSHOT"] ?? "nil")")
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
