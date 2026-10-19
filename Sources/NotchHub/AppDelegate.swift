import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?

    let clipboard = ClipboardStore()
    let screenshots = ScreenshotStore()
    let nowPlaying = NowPlayingStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = Snapshot.outputDir, Snapshot.isDemo {
            Snapshot.renderDemo(to: dir, clipboard: clipboard, screenshots: screenshots, nowPlaying: nowPlaying)
            NSApp.terminate(nil)
            return
        }

        clipboard.start()
        screenshots.start()
        nowPlaying.start()

        if let dir = Snapshot.outputDir {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                screenshots.items.forEach { screenshots.thumbnail(for: $0) { _ in } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [self] in
                Snapshot.render(to: dir, clipboard: clipboard, screenshots: screenshots, nowPlaying: nowPlaying)
                NSApp.terminate(nil)
            }
            return
        }

        notchController = NotchWindowController(clipboard: clipboard, screenshots: screenshots, nowPlaying: nowPlaying)
        notchController?.show()

        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        notchController?.reposition()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchHub")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Очистить буфер обмена", action: #selector(clearClipboard), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти из NotchHub", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action == #selector(clearClipboard) { $0.target = self } }
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying.stop()
    }

    @objc private func clearClipboard() {
        clipboard.clear()
    }
}
