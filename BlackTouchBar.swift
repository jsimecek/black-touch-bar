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

private enum TouchBarID {
    static let blackout = NSTouchBarItem.Identifier("com.local.blackout")
    static let escapeBlackout = NSTouchBarItem.Identifier("com.local.blackout.esc")
}

private enum Defaults {
    static let controlStripSuite = "com.apple.touchbar.agent"
    static let presentationModeKey = "PresentationModeGlobal"
}

// Detects Cmd double-press while filtering out Cmd+key shortcuts.
final class DoubleTapDetector {
    var onDoubleTap: (() -> Void)?
    var onFnKeyChanged: ((Bool) -> Void)?
    private(set) var isFnDown = false

    private let interval: TimeInterval = 0.4
    private var lastCmdPressTime: TimeInterval = 0
    private var wasCmdDown = false
    private var hadKeyPressSinceLastCmdDown = false
    private var eventTap: CFMachPort?

    func start() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            self?.handleFlagsChanged($0)
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            self?.handleFlagsChanged($0)
            return $0
        }
        installKeyDownTap()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        let isFnDown = flags.contains(.function)
        let isCmdDown = flags.contains(.command)
        let hasOtherModifiers = !flags.intersection([.shift, .option, .control]).isEmpty

        if isFnDown != self.isFnDown {
            self.isFnDown = isFnDown
            onFnKeyChanged?(isFnDown)
        }

        defer { wasCmdDown = isCmdDown }
        guard isCmdDown, !wasCmdDown, !hasOtherModifiers else { return }

        let now = ProcessInfo.processInfo.systemUptime

        if hadKeyPressSinceLastCmdDown {
            lastCmdPressTime = now
            hadKeyPressSinceLastCmdDown = false
            return
        }

        hadKeyPressSinceLastCmdDown = false

        guard now - lastCmdPressTime < interval else {
            lastCmdPressTime = now
            return
        }

        lastCmdPressTime = 0
        DispatchQueue.main.async { [self] in onDoubleTap?() }
    }

    // Don't falsely count Cmd+key shortcuts as Cmd press. Requires Input Monitoring permission.
    private func installKeyDownTap() {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                let detector = Unmanaged<DoubleTapDetector>.fromOpaque(refcon!).takeUnretainedValue()
                switch type {
                case .keyDown:
                    detector.hadKeyPressSinceLastCmdDown = true
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    if let tap = detector.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                default:
                    break
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

enum KeyboardBacklight {
    static func setBrightness(_ value: Float) {
        guard
            let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
            bundle.isLoaded || bundle.load(),
            let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return }

        typealias SetBrightnessFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

        let client = clientClass.init()
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        let imp = unsafeBitCast((client as AnyObject).method(for: sel), to: SetBrightnessFn.self)
        _ = imp(client, sel, value, 1)
    }
}

enum ControlStrip {
    static func kill() {
        run("/usr/bin/killall", arguments: ["ControlStrip"])
    }

    static var isRunning: Bool {
        run("/usr/bin/pgrep", arguments: ["-x", "ControlStrip"]) == 0
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private let touchBarDefaults = UserDefaults(suiteName: Defaults.controlStripSuite)!
    private let detector = DoubleTapDetector()
    private let respawnPollInterval: TimeInterval = 0.02
    private let respawnTimeout: TimeInterval = 0.5

    private var isBlackedOut = false
    private var modalTouchBar: NSTouchBar?
    private var pendingBlackout: DispatchWorkItem?
    private var savedPresentationMode: String?

    func applicationDidFinishLaunching(_: Notification) {
        detector.onDoubleTap = { [weak self] in self?.toggle() }
        detector.onFnKeyChanged = { [weak self] isDown in self?.handleFnKey(isDown: isDown) }
        detector.start()

        // Allows toggling via scripts or Shortcuts (e.g. toggle-touchbar.sh)
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

    @objc private func toggle() {
        isBlackedOut.toggle()
        isBlackedOut ? blackOut() : restore()
    }

    private func blackOut() {
        KeyboardBacklight.setBrightness(0)

        // Switch to "app" mode so other modes don't bypass the overlay
        savedPresentationMode = touchBarDefaults.string(forKey: Defaults.presentationModeKey)
        touchBarDefaults.set("app", forKey: Defaults.presentationModeKey)
        ControlStrip.kill() // Force ControlStrip to restart to pick up the new mode

        let work = DispatchWorkItem { [self] in
            let bar = NSTouchBar()
            bar.delegate = self
            bar.defaultItemIdentifiers = [TouchBarID.blackout]
            bar.escapeKeyReplacementItemIdentifier = TouchBarID.escapeBlackout
            modalTouchBar = bar

            guard !detector.isFnDown else { return }
            NSTouchBar.presentSystemModal(bar, identifier: TouchBarID.blackout)
        }
        pendingBlackout = work

        // Present once ControlStrip has respawned, otherwise it overrides the overlay
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            let deadline = Date().addingTimeInterval(respawnTimeout)
            while Date() < deadline {
                guard !work.isCancelled else { return }
                if ControlStrip.isRunning { break }
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
        touchBarDefaults.set(mode, forKey: Defaults.presentationModeKey)
        ControlStrip.kill()
    }

    private func handleFnKey(isDown: Bool) {
        guard isBlackedOut, let bar = modalTouchBar else { return }

        if isDown {
            NSTouchBar.dismissSystemModal(bar)
        } else {
            NSTouchBar.presentSystemModal(bar, identifier: TouchBarID.blackout)
        }
    }

    func touchBar(
        _: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        item.view = view
        return item
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon, no menu bar
let delegate = AppDelegate()
app.delegate = delegate
app.run()
