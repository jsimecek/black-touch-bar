import AppKit

// Private NSTouchBar API for system-modal overlays. These selectors are not part of the
// public SDK and may break in future macOS versions.
extension NSTouchBar {
    static func presentSystemModal(_ touchBar: NSTouchBar, identifier: NSTouchBarItem.Identifier) {
        let selector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        let method = unsafeBitCast(
            (self as AnyObject).method(for: selector),
            to: (@convention(c) (AnyObject, Selector, NSTouchBar, Int, Any?) -> Void).self
        )
        method(self, selector, touchBar, 1, identifier) // placement 1 = replace entire Touch Bar
    }

    static func minimizeSystemModal(_ touchBar: NSTouchBar) {
        let selector = NSSelectorFromString("minimizeSystemModalTouchBar:")
        _ = (self as AnyObject).perform(selector, with: touchBar)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    let blackoutID = NSTouchBarItem.Identifier("com.local.blackout")
    let escBlackID = NSTouchBarItem.Identifier("com.local.blackout.esc")
    let touchBarDefaults = UserDefaults(suiteName: "com.apple.touchbar.agent")! // ControlStrip's prefs
    let doubleTapInterval: TimeInterval = 0.4

    var isBlacked = false
    var modalTouchBar: NSTouchBar?
    var pendingBlackout: DispatchWorkItem?
    var savedPresentationMode: String?
    var lastCmdPressTime: TimeInterval = 0
    var wasCmdDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeDoubleCmdPress()

        // Allow toggling via scripts / Shortcuts (e.g. toggle-touchbar.sh)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(toggle),
            name: NSNotification.Name("com.local.BlackTouchBar.toggle"),
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard isBlacked else { return }
        restore()
    }

    func observeDoubleCmdPress() {
        // Global catches events in other apps, local catches events in this app
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            self?.handleFlagsChanged($0)
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            self?.handleFlagsChanged($0)
            return $0
        }
    }

    func handleFlagsChanged(_ event: NSEvent) {
        let isCmdDown = event.modifierFlags.contains(.command)
        let hasOtherModifiers = !event.modifierFlags.intersection([.shift, .option, .control]).isEmpty

        defer { wasCmdDown = isCmdDown }

        guard isCmdDown, !wasCmdDown, !hasOtherModifiers else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCmdPressTime < doubleTapInterval else {
            lastCmdPressTime = now
            return
        }

        lastCmdPressTime = 0
        DispatchQueue.main.async { [self] in toggle() }
    }

    @objc func toggle() {
        isBlacked.toggle()
        isBlacked ? blackOut() : restore()
    }

    func blackOut() {
        // Switch to "app" mode so the function keys layer doesn't bypass the overlay
        savedPresentationMode = touchBarDefaults.string(forKey: "PresentationModeGlobal")
        touchBarDefaults.set("app", forKey: "PresentationModeGlobal")
        killControlStrip() // Force ControlStrip to restart and pick up the new mode

        // Wait for ControlStrip to respawn before presenting, otherwise it can override the overlay
        let work = DispatchWorkItem { [self] in
            let bar = NSTouchBar()
            bar.delegate = self
            bar.defaultItemIdentifiers = [blackoutID]
            bar.escapeKeyReplacementItemIdentifier = escBlackID
            modalTouchBar = bar
            NSTouchBar.presentSystemModal(bar, identifier: blackoutID)
        }
        pendingBlackout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func restore() {
        pendingBlackout?.cancel()
        pendingBlackout = nil

        if let bar = modalTouchBar {
            NSTouchBar.minimizeSystemModal(bar)
            modalTouchBar = nil
        }

        let mode = savedPresentationMode ?? "functionKeys"
        touchBarDefaults.set(mode, forKey: "PresentationModeGlobal")
        killControlStrip()
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["ControlStrip"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon, no menu bar
let delegate = AppDelegate()
app.delegate = delegate
app.run()
