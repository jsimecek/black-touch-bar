import AppKit

// MARK: - Private DFRFoundation API

/// Controls whether the system-modal Touch Bar shows a close (X) button
/// when the presenting app is frontmost.
@_silgen_name("DFRSystemModalShowsCloseBoxWhenFrontMost")
func DFRSystemModalShowsCloseBoxWhenFrontMost(_ shows: Bool)

// MARK: - NSTouchBar private extensions for system-modal presentation

extension NSTouchBar {
    /// Present a system-modal Touch Bar that overlays all other Touch Bar content.
    static func presentSystemModal(_ touchBar: NSTouchBar, identifier: NSTouchBarItem.Identifier) {
        for name in [
            "presentSystemModalTouchBar:systemTrayItemIdentifier:",
            "presentSystemModalFunctionBar:systemTrayItemIdentifier:",
        ] {
            let sel = NSSelectorFromString(name)
            if self.responds(to: sel) {
                _ = (self as AnyObject).perform(sel, with: touchBar, with: identifier)
                return
            }
        }
    }

    /// Dismiss the currently presented system-modal Touch Bar.
    static func dismissSystemModal() {
        for name in [
            "dismissSystemModalTouchBar:",
            "dismissSystemModalFunctionBar:",
        ] {
            let sel = NSSelectorFromString(name)
            if self.responds(to: sel) {
                _ = (self as AnyObject).perform(sel, with: NSTouchBar())
                return
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    var statusItem: NSStatusItem?
    var isBlacked = false
    let blackoutID = NSTouchBarItem.Identifier("com.local.blackout")
    var savedPresentationMode: String?
    var lastCmdPressTime: TimeInterval = 0
    var cmdWasDown = false

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

    // MARK: - Double-press Cmd detection

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

    // MARK: - Toggle

    @objc func toggle() {
        isBlacked.toggle()
        if isBlacked { blackOut() } else { restore() }
    }

    func blackOut() {
        // Save current Touch Bar mode and switch to "app" (no control strip)
        savedPresentationMode = readDefault("PresentationModeGlobal")
        writeDefault("PresentationModeGlobal", "app")
        run("/usr/bin/killall", ["ControlStrip"])

        // After ControlStrip restarts, present the black overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            DFRSystemModalShowsCloseBoxWhenFrontMost(false)
            let tb = NSTouchBar()
            tb.delegate = self
            tb.defaultItemIdentifiers = [blackoutID]
            NSTouchBar.presentSystemModal(tb, identifier: blackoutID)
            DFRSystemModalShowsCloseBoxWhenFrontMost(false)
            statusItem?.button?.title = "TB off"
        }
    }

    func restore() {
        NSTouchBar.dismissSystemModal()
        let mode = savedPresentationMode ?? "functionKeys"
        writeDefault("PresentationModeGlobal", mode)
        run("/usr/bin/killall", ["ControlStrip"])
        statusItem?.button?.title = "TB on"
    }

    // MARK: - NSTouchBarDelegate

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

    // MARK: - Helpers

    func readDefault(_ key: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["read", "com.apple.touchbar.agent", key]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func writeDefault(_ key: String, _ value: String) {
        run("/usr/bin/defaults", ["write", "com.apple.touchbar.agent", key, "-string", value])
    }

    func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    @objc func quit() {
        if isBlacked { restore() }
        NSApp.terminate(nil)
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
