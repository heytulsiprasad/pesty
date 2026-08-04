import AppKit
import SwiftUI

enum Theme {
    // Card height is barHeight minus the 56pt toolbar and 22pt of strip padding.
    // At the default barHeight of 300 that is 222pt, so the width sits just above
    // it to stay slightly wider than tall — the proportion Paste uses.
    static let cardWidth: CGFloat = 232
    static let cardSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 18
    static let cardCorner: CGFloat = 13
    static let headerHeight: CGFloat = 50

    /// Resolves per appearance, so the strip follows the system theme instead of
    /// being pinned to one. Light is the Paste-style palette; dark restores the
    /// values this project shipped before the restyle.
    private static func dyn(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func white(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }
    private static func black(_ a: CGFloat) -> NSColor { NSColor(white: 0, alpha: a) }

    static let panelTint = dyn(light: white(0.62), dark: black(0.34))

    static let cardBody = dyn(light: white(1.0),
                              dark: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    static let cardBorder = dyn(light: black(0.07), dark: white(0.07))
    static let selection = Color(red: 0.20, green: 0.55, blue: 1.0)

    static let textPrimary = dyn(light: black(0.88), dark: white(0.95))
    static let textSecondary = dyn(light: black(0.50), dark: white(0.55))
    static let textTertiary = dyn(light: black(0.30), dark: white(0.34))

    // Header text sits on a saturated color band in both themes, so it stays white.
    static let headerText = Color.white
    static let headerSubText = Color.white.opacity(0.82)

    static let fieldBG = dyn(light: black(0.06), dark: white(0.09))
    static let pillBG = dyn(light: black(0.05), dark: white(0.10))
    static let pillSelected = dyn(light: white(0.95), dark: white(0.18))

    /// Shadows have to invert too: a black drop shadow is invisible on a dark panel.
    static let cardShadow = dyn(light: black(0.10), dark: black(0.45))
    static let cardShadowSelected = dyn(light: black(0.22), dark: black(0.65))
}

extension Date {
    var clipRelative: String {
        let secs = -timeIntervalSinceNow
        switch secs {
        case ..<5:        return "Now"
        case ..<60:       return "\(Int(secs))s"
        case ..<3600:     return "\(Int(secs / 60))m"
        case ..<86_400:   return "\(Int(secs / 3600))h"
        case ..<604_800:  return "\(Int(secs / 86_400))d"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: self)
        }
    }

    var clipRelativeLong: String {
        let secs = -timeIntervalSinceNow
        if secs < 8 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: Date())
    }
}
