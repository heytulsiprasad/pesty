import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppController()

    let store = ClipboardStore.shared
    let monitor = ClipboardMonitor()

    private var barController: BarWindowController?
    private var previewController: PreviewWindowController?
    private var statusItem: NSStatusItem?
    private var openItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?

    private(set) var previousApp: NSRunningApplication?
    private(set) var lastActiveApp: NSRunningApplication?

    var suppressAutoHide = false

    /// Two login items — the SMAppService one and a hand-added one pointing at a
    /// second copy of the bundle — launched two Pestys at login. Both registered
    /// the hotkey, so one press showed two strips and the next hid one. The newest
    /// process wins: it asks older copies to quit, and an older copy that finds a
    /// newer one already running quits itself. `restart()` relies on this — the
    /// relaunched copy takes over from the one that spawned it.
    ///
    /// Runs from main() before `shared` exists, so a losing copy never loads the
    /// store and the winner loads it only after the copy it replaces has flushed
    /// its last save and gone. Nobody terminates anybody — the App Sandbox build
    /// could not, `terminate()` is refused there — each copy decides for itself:
    /// yield to a newer copy at once; give an older copy a moment to leave, which
    /// is what `restart()` looks like from here (it spawns us, then quits); and if
    /// the older copy is still there, it is the running app and we are the extra.
    ///
    /// ponytail: pid order stands in for launch order. It only misorders across a
    /// pid wrap, which needs two launches racing at that exact moment.
    static func claimSingleInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        func others() -> [pid_t] {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .map(\.processIdentifier).filter { $0 != me }
        }
        if others().contains(where: { $0 > me }) { exit(0) }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, others().contains(where: { $0 < me }) { usleep(50_000) }
        if others().contains(where: { $0 < me }) { exit(0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        monitor.start()

        HotKeyCenter.shared.onTrigger = { [weak self] in self?.toggleBar() }
        HotKeyCenter.shared.start()

        setupStatusItem()

        if Settings.shared.launchAtLogin { LaunchAtLogin.set(enabled: true) }

        if CommandLine.arguments.contains("--demo") {
            store.seedDemo()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showBar()
            }
            return
        }

        if !Settings.shared.onboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showSettings()
            }
            Settings.shared.onboarded = true
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastActiveApp = app
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "", action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        openItem = open
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Clear History", action: #selector(menuClear), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let about = menu.addItem(withTitle: "About Pesty", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(withTitle: "Quit Pesty", action: #selector(menuQuit), keyEquivalent: "q").target = self
        menu.delegate = self
        item.menu = menu
        statusItem = item

        HotKeyCenter.shared.onRegistrationChange = { [weak self] _ in self?.refreshStatusItem() }
        refreshStatusItem()
    }

    /// The status item advertises the shortcut, so it cannot be filled in once and
    /// left alone: the user can rebind it, and macOS can refuse to register it. A
    /// refused shortcut is otherwise invisible — the icon sits there looking healthy
    /// while nothing responds — so the icon carries the warning too.
    private func refreshStatusItem() {
        let live = HotKeyCenter.shared.isRegistered
        let shortcut = Settings.shared.hotkeyDisplay
        openItem?.title = live
            ? "Open Pesty   \(shortcut)"
            : "Open Pesty   —   \(shortcut) did not register"
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: live ? "doc.on.clipboard" : "exclamationmark.triangle",
                accessibilityDescription: live ? "Pesty" : "Pesty — shortcut unavailable")
            button.image?.isTemplate = true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refreshStatusItem() }

    @objc private func menuOpen() { showBar() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuClear() { store.clearHistory() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuAbout() { showAbout() }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Pesty",
            .applicationVersion: Bundle.main.appVersion,
            .credits: NSAttributedString(
                string: "A free, open-source clipboard manager for macOS.\nInspired by Paste.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)])
        ])
    }

    func toggleICloudSync() {
        let enabling = !Settings.shared.iCloudSync
        if enabling && !ClipboardStore.shared.iCloudAvailable {
            let alert = NSAlert()
            alert.messageText = "iCloud Drive Unavailable"
            alert.informativeText = "Sign in to iCloud and enable iCloud Drive in System Settings to sync your clipboard across your Macs."
            alert.runModal()
            return
        }
        Settings.shared.iCloudSync = enabling
        ClipboardStore.shared.setICloudSync(enabling)
    }

    static func restart() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    func toggleBar() {
        if let bar = barController, bar.window?.isVisible == true {
            hideBar()
        } else {
            showBar()
        }
    }

    func showBar() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        store.selectFirst()

        if barController == nil {
            barController = BarWindowController()
        }
        barController?.show()
        startKeyMonitor()
    }

    /// The search and tab reset on the way down, not in showBar: the strip animates
    /// every reorder, and resetting on the way up made the cards visibly reshuffle
    /// as the bar rose.
    func hideBar() {
        closePreview()
        stopKeyMonitor()
        store.searchText = ""
        store.source = .history
        barController?.hide()
    }

    /// Tab walks Clipboard → each pinboard → back to Clipboard; Shift-Tab reverses.
    func cycleSource(by delta: Int) {
        var sources: [BarSource] = [.history]
        sources.append(contentsOf: store.pinboards.map { BarSource.pinboard($0.id) })
        guard sources.count > 1 else { return }
        let cur = sources.firstIndex(of: store.source) ?? 0
        let n = sources.count
        store.source = sources[((cur + delta) % n + n) % n]
        store.selectFirst()
    }

    func togglePreview() {
        if previewController?.isOpen == true { closePreview(); return }
        guard let item = store.selectedItem else { return }
        if previewController == nil { previewController = PreviewWindowController() }
        // The preview takes key away from the strip, which would otherwise auto-hide.
        suppressAutoHide = true
        previewController?.show(item: item)
    }

    func closePreview() {
        guard previewController?.isOpen == true else { return }
        previewController?.hide()
        suppressAutoHide = false
        barController?.window?.makeKeyAndOrderFront(nil)
    }

    func pasteSelected() {
        guard let item = store.selectedItem else { return }
        pasteItem(item)
    }

    func pasteItem(_ item: ClipItem) {
        hideBar()
        PasteService.paste(item, into: previousApp, monitor: monitor)
        store.promote(item)
    }

    /// Copy keeps the strip open, unlike paste: the point of the slide-to-front is
    /// that the user watches the card become the newest clip.
    func copyItem(_ item: ClipItem) {
        let change = PasteService.copy(item)
        monitor.suppressUntilChangeCount = change
        store.promote(item)
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView()
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "Pesty Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 520, height: 560))
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// ⌥⌫ semantics: drop trailing whitespace, then the word before the caret.
    static func deletingLastWord(_ s: String) -> String {
        var t = Substring(s)
        while let c = t.last, c.isWhitespace { t = t.dropLast() }
        while let c = t.last, !c.isWhitespace { t = t.dropLast() }
        return String(t)
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let code = Int(event.keyCode)
        let flags = event.modifierFlags
        let cmd = flags.contains(.command)
        let ctrl = flags.contains(.control)
        let opt = flags.contains(.option)

        if cmd, let chars = event.charactersIgnoringModifiers, let n = Int(chars), (1...9).contains(n) {
            let items = store.visibleItems
            if n <= items.count { pasteItem(items[n - 1]) }
            return nil
        }

        // Space is Quick Look, but only when nothing is typed — otherwise a multi-word
        // search would be impossible.
        if code == kVK_Space, !cmd, !ctrl, !opt, store.searchText.isEmpty {
            togglePreview()
            return nil
        }
        // Any other key while the preview is open dismisses it first, so the strip
        // never acts on a keystroke the user aimed at the preview.
        if previewController?.isOpen == true, code != kVK_Space {
            closePreview()
        }

        if cmd, !ctrl, !opt, code == kVK_ANSI_C {
            if let item = store.selectedItem { copyItem(item) }
            return nil
        }

        switch code {
        case kVK_Tab:
            cycleSource(by: flags.contains(.shift) ? -1 : 1)
            return nil
        case kVK_Escape:
            if previewController?.isOpen == true { closePreview() }
            else if !store.searchText.isEmpty { store.searchText = ""; store.selectFirst() }
            else { hideBar() }
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            pasteSelected(); return nil
        case kVK_LeftArrow, kVK_UpArrow:
            store.moveSelection(by: -1); return nil
        case kVK_RightArrow, kVK_DownArrow:
            store.moveSelection(by: 1); return nil
        case kVK_Delete:
            // An active search owns the delete keys. ⌘⌫ must NOT fall through to
            // deleting the selected clip here — pressing it to clear the field was
            // silently destroying history instead.
            if !store.searchText.isEmpty {
                if cmd {
                    store.searchText = ""
                } else if opt {
                    store.searchText = Self.deletingLastWord(store.searchText)
                } else {
                    store.searchText.removeLast()
                }
                store.selectFirst()
                return nil
            }
            if cmd, let sel = store.selectedItem { store.delete(sel) }
            return nil
        case kVK_ForwardDelete:
            if let sel = store.selectedItem { store.delete(sel) }
            return nil
        default:
            break
        }

        if !cmd && !ctrl && !opt,
           let chars = event.characters, chars.count == 1,
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 32, scalar.value != 127 {
            store.searchText.append(chars)
            store.selectFirst()
            return nil
        }
        return event
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
