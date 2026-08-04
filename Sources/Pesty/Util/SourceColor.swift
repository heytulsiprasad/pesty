import SwiftUI

@MainActor
enum SourceColor {
    // High-chroma header colors. The muted originals read as washed out against the
    // light card surface; Paste's headers are fully saturated.
    private static let palette: [Color] = [
        Color(red: 0.18, green: 0.51, blue: 0.96),   // blue
        Color(red: 0.90, green: 0.24, blue: 0.29),   // red
        Color(red: 0.96, green: 0.62, blue: 0.11),   // amber
        Color(red: 0.13, green: 0.73, blue: 0.37),   // green
        Color(red: 0.85, green: 0.22, blue: 0.51),   // pink
        Color(red: 0.49, green: 0.31, blue: 0.90),   // violet
        Color(red: 0.02, green: 0.68, blue: 0.75),   // teal
        Color(red: 0.96, green: 0.42, blue: 0.15),   // orange
        Color(red: 0.35, green: 0.36, blue: 0.92),   // indigo
        Color(red: 0.60, green: 0.72, blue: 0.10),   // lime
        Color(red: 0.78, green: 0.16, blue: 0.72),   // magenta
        Color(red: 0.10, green: 0.60, blue: 0.88)    // sky
    ]

    private static let key = "appColorMap"
    private static var map: [String: Int] = {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }()

    static func color(for bundleID: String?) -> Color {
        guard let id = bundleID, !id.isEmpty else { return palette[0] }
        if let i = map[id] { return palette[i % palette.count] }
        let i = map.count % palette.count
        map[id] = i
        UserDefaults.standard.set(map, forKey: key)
        return palette[i]
    }
}
