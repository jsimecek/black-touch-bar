import AppKit

extension NSTouchBar {
    /// Present a system-modal Touch Bar that overlays all other Touch Bar content.
    static func presentSystemModal(_ touchBar: NSTouchBar, identifier: NSTouchBarItem.Identifier) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        let method = unsafeBitCast(
            (self as AnyObject).method(for: sel),
            to: (@convention(c) (AnyObject, Selector, NSTouchBar, Int, Any?) -> Void).self
        )
        method(self, sel, touchBar, 1, identifier)
    }

    /// Minimize (hide) the currently presented system-modal Touch Bar.
    static func minimizeSystemModal(_ touchBar: NSTouchBar) {
        let sel = NSSelectorFromString("minimizeSystemModalTouchBar:")
        _ = (self as AnyObject).perform(sel, with: touchBar)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    var statusItem: NSStatusItem?
    var isBlacked = false
    let blackoutID = NSTouchBarItem.Identifier("com.local.blackout")
    let escBlackID = NSTouchBarItem.Identifier("com.local.blackout.esc")
    var modalTouchBar: NSTouchBar?
    var savedPresentationMode: String?
    var lastCmdPressTime: TimeInterval = 0
    var cmdWasDown = false
    let touchBarDefaults = UserDefaults(suiteName: "com.apple.touchbar.agent")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "TB"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Touch Bar", action: #selector(toggle), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu

        setupDoubleCmdDetection()

        // Allow toggling via distributed notification (for scripts / Shortcuts)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(toggle),
            name: NSNotification.Name("com.local.BlackTouchBar.toggle"),
            object: nil
        )
    }

    func setupDoubleCmdDetection() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
    }

    func handleFlags(_ event: NSEvent) {
        let cmdDown = event.modifierFlags.contains(.command)
        let otherMods: NSEvent.ModifierFlags = [.shift, .option, .control]
        let hasOtherMods = !event.modifierFlags.intersection(otherMods).isEmpty

        if cmdDown && !cmdWasDown && !hasOtherMods {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastCmdPressTime < 0.4 {
                lastCmdPressTime = 0
                DispatchQueue.main.async { self.toggle() }
            } else {
                lastCmdPressTime = now
            }
        }
        cmdWasDown = cmdDown
    }

    @objc func toggle() {
        isBlacked.toggle()
        if isBlacked { blackOut() } else { restore() }
    }

    func blackOut() {
        // Save current Touch Bar mode and switch to "app" (removes F-keys layer)
        savedPresentationMode = touchBarDefaults.string(forKey: "PresentationModeGlobal")
        touchBarDefaults.set("app", forKey: "PresentationModeGlobal")
        killControlStrip()

        // After ControlStrip restarts, present the black overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            let tb = NSTouchBar()
            tb.delegate = self
            tb.defaultItemIdentifiers = [blackoutID]
            tb.escapeKeyReplacementItemIdentifier = escBlackID
            modalTouchBar = tb
            NSTouchBar.presentSystemModal(tb, identifier: blackoutID)
            statusItem?.button?.title = "TB off"
        }
    }

    func restore() {
        // Remove the black overlay
        if let tb = modalTouchBar {
            NSTouchBar.minimizeSystemModal(tb)
            modalTouchBar = nil
        }

        touchBarDefaults.set(savedPresentationMode ?? "functionKeys", forKey: "PresentationModeGlobal")
        killControlStrip()
        statusItem?.button?.title = "TB on"
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        item.view = view
        return item
    }

    func killControlStrip() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["ControlStrip"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    @objc func quit() {
        if isBlacked { restore() }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
