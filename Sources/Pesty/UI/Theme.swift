import SwiftUI

enum Theme {
    // Card body height is barHeight (370) minus the toolbar and strip padding, so
    // ~292pt. Width is set just above that to land slightly wider than tall, the
    // proportion Paste uses — 252 read as portrait.
    static let cardWidth: CGFloat = 304
    static let cardSpacing: CGFloat = 14
    static let cornerRadius: CGFloat = 18
    static let cardCorner: CGFloat = 14
    static let headerHeight: CGFloat = 58

    // Light panel. The window forces an aqua appearance so the underlying
    // material stays light even when the system is in dark mode, which is how
    // the panel picks up the desktop wallpaper the way Paste's strip does.
    static let panelTint = Color.white.opacity(0.62)

    static let cardBody = Color.white
    static let cardBorder = Color.black.opacity(0.07)
    static let selection = Color(red: 0.20, green: 0.55, blue: 1.0)

    static let textPrimary = Color.black.opacity(0.88)
    static let textSecondary = Color.black.opacity(0.50)
    static let textTertiary = Color.black.opacity(0.30)

    static let headerText = Color.white
    static let headerSubText = Color.white.opacity(0.82)

    static let fieldBG = Color.black.opacity(0.06)
    static let pillBG = Color.black.opacity(0.05)
    static let pillSelected = Color.white.opacity(0.95)
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
