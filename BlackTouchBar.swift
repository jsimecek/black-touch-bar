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

    static func dismissSystemModal(_ touchBar: NSTouchBar) {
        let selector = NSSelectorFromString("dismissSystemModalTouchBar:")
        _ = (self as AnyObject).perform(selector, with: touchBar)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private let blackoutID = NSTouchBarItem.Identifier("com.local.blackout")
    private let escBlackID = NSTouchBarItem.Identifier("com.local.blackout.esc")
    private let touchBarDefaults = UserDefaults(suiteName: "com.apple.touchbar.agent")! // ControlStrip's prefs
    private let doubleTapInterval: TimeInterval = 0.4
    private let respawnPollInterval: TimeInterval = 0.02
    private let respawnTimeout: TimeInterval = 0.5

    private var isBlackedOut = false
    private var modalTouchBar: NSTouchBar?
    private var pendingBlackout: DispatchWorkItem?
    private var savedPresentationMode: String?
    private var lastCmdPressTime: TimeInterval = 0
    private var wasCmdDown = false
    private var wasFnDown = false

    func applicationDidFinishLaunching(_: Notification) {
        observeDoubleCmdPress()

        // Allow toggling via scripts / Shortcuts (e.g. toggle-touchbar.sh)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(toggle),
            name: NSNotification.Name("com.local.BlackTouchBar.toggle"),
            object: nil
        )
    }

    func applicationWillTerminate(_: Notification) {
        guard isBlackedOut else { return }
        restore()
    }

    private func observeDoubleCmdPress() {
        // Global catches events in other apps, local catches events in this app
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            self?.handleFlagsChanged($0)
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            self?.handleFlagsChanged($0)
            return $0
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isFnDown = event.modifierFlags.contains(.function)
        if isFnDown != wasFnDown {
            wasFnDown = isFnDown
            handleFnKey(isDown: isFnDown)
        }

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

    private func handleFnKey(isDown: Bool) {
        guard isBlackedOut, let bar = modalTouchBar else { return }

        if isDown {
            NSTouchBar.dismissSystemModal(bar)
        } else {
            NSTouchBar.presentSystemModal(bar, identifier: blackoutID)
        }
    }

    @objc private func toggle() {
        isBlackedOut.toggle()
        isBlackedOut ? blackOut() : restore()
    }

    private func blackOut() {
        // Turn off the keyboard backlight
        setKeyboardBacklight(0)

        // Switch to "app" mode so other modes don't bypass the overlay
        savedPresentationMode = touchBarDefaults.string(forKey: "PresentationModeGlobal")
        touchBarDefaults.set("app", forKey: "PresentationModeGlobal")
        killControlStrip() // Force ControlStrip to restart and pick up the new mode

        let work = DispatchWorkItem { [self] in
            let bar = NSTouchBar()
            bar.delegate = self
            bar.defaultItemIdentifiers = [blackoutID]
            bar.escapeKeyReplacementItemIdentifier = escBlackID
            modalTouchBar = bar

            guard !wasFnDown else { return }
            NSTouchBar.presentSystemModal(bar, identifier: blackoutID)
        }
        pendingBlackout = work

        // Present once ControlStrip has respawned, otherwise it overrides the overlay
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            let deadline = Date().addingTimeInterval(respawnTimeout)
            while Date() < deadline {
                guard !work.isCancelled else { return }
                if isControlStripRunning() { break }
                Thread.sleep(forTimeInterval: respawnPollInterval)
            }
            DispatchQueue.main.async(execute: work)
        }
    }

    private func restore() {
        pendingBlackout?.cancel()
        pendingBlackout = nil

        if let bar = modalTouchBar {
            NSTouchBar.dismissSystemModal(bar)
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

    private func setKeyboardBacklight(_ brightness: Float) {
        guard
            let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
            bundle.isLoaded || bundle.load(),
            let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return }

        typealias SetBrightnessFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

        let client = clientClass.init()
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        let setBrightness = unsafeBitCast((client as AnyObject).method(for: sel), to: SetBrightnessFn.self)
        _ = setBrightness(client, sel, brightness, 1)
    }

    private func killControlStrip() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["ControlStrip"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func isControlStripRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "ControlStrip"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon, no menu bar
let delegate = AppDelegate()
app.delegate = delegate
app.run()
