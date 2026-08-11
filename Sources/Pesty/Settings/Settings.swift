import AppKit
import Carbon.HIToolbox
import Observation

@Observable
@MainActor
final class Settings {
    static let shared = Settings()

    @ObservationIgnored private let d = UserDefaults.standard
    @ObservationIgnored private var isLoaded = false

    enum Keys {
        static let historyLimit = "historyLimit"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let launchAtLogin = "launchAtLogin"
        static let pasteDirectly = "pasteDirectly"
        static let playSound = "playSound"
        static let ignoreConcealed = "ignoreConcealed"
        static let barHeight = "barHeight"
        static let onboarded = "onboarded"
        static let iCloudSync = "iCloudSync"
    }

    var historyLimit: Int {
        didSet {
            guard isLoaded else { return }
            if historyLimit < 20 { historyLimit = 20; return }
            d.set(historyLimit, forKey: Keys.historyLimit)
            ClipboardStore.shared.applyHistoryLimit()
        }
    }

    /// Set through `setHotkey(keyCode:modifiers:)`, never one at a time — see there.
    private(set) var hotkeyKeyCode: Int {
        didSet { guard isLoaded else { return }; d.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    private(set) var hotkeyModifiers: Int {
        didSet { guard isLoaded else { return }; d.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    var launchAtLogin: Bool {
        didSet { guard isLoaded else { return }
            d.set(launchAtLogin, forKey: Keys.launchAtLogin); LaunchAtLogin.set(enabled: launchAtLogin) }
    }

    var pasteDirectly: Bool {
        didSet { guard isLoaded else { return }; d.set(pasteDirectly, forKey: Keys.pasteDirectly) }
    }

    var playSound: Bool {
        didSet { guard isLoaded else { return }; d.set(playSound, forKey: Keys.playSound) }
    }

    var ignoreConcealed: Bool {
        didSet { guard isLoaded else { return }; d.set(ignoreConcealed, forKey: Keys.ignoreConcealed) }
    }

    var barHeight: Double {
        didSet {
            guard isLoaded else { return }
            let clamped = min(720, max(240, barHeight))
            if clamped != barHeight { barHeight = clamped; return }
            d.set(barHeight, forKey: Keys.barHeight)
        }
    }

    var onboarded: Bool {
        didSet { guard isLoaded else { return }; d.set(onboarded, forKey: Keys.onboarded) }
    }

    var iCloudSync: Bool {
        didSet { guard isLoaded else { return }; d.set(iCloudSync, forKey: Keys.iCloudSync) }
    }

    private init() {
        d.register(defaults: [
            Keys.historyLimit: 500,
            Keys.hotkeyKeyCode: kVK_ANSI_V,
            Keys.hotkeyModifiers: cmdKey | shiftKey,
            Keys.launchAtLogin: false,
            Keys.pasteDirectly: true,
            Keys.playSound: false,
            Keys.ignoreConcealed: true,
            Keys.barHeight: 430.0,
            Keys.onboarded: false,
            Keys.iCloudSync: false
        ])
        historyLimit = d.integer(forKey: Keys.historyLimit)
        hotkeyKeyCode = d.integer(forKey: Keys.hotkeyKeyCode)
        hotkeyModifiers = d.integer(forKey: Keys.hotkeyModifiers)
        launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        pasteDirectly = d.bool(forKey: Keys.pasteDirectly)
        playSound = d.bool(forKey: Keys.playSound)
        ignoreConcealed = d.bool(forKey: Keys.ignoreConcealed)
        barHeight = d.double(forKey: Keys.barHeight)
        onboarded = d.bool(forKey: Keys.onboarded)
        iCloudSync = d.bool(forKey: Keys.iCloudSync)
        isLoaded = true
    }

    /// Writes both halves of the shortcut, then re-registers once.
    ///
    /// Assigning the two properties separately used to reload the hotkey twice, and
    /// the first pass registered a combination the user never asked for — the new key
    /// code paired with the old modifiers. That intermediate shortcut is live long
    /// enough to fire, and it can lose the race for a combination another app owns.
    ///
    /// Returns whether the new shortcut registered; the caller decides what to do
    /// when it did not.
    @discardableResult
    func setHotkey(keyCode: Int, modifiers: Int) -> Bool {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        return HotKeyCenter.shared.reload()
    }

    var hotkeyDisplay: String {
        HotKeyCenter.describe(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }
}
