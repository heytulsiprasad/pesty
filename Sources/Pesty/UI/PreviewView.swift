import AppKit
import SwiftUI

/// Large preview of a single clip. Every ClipType gets a real renderer — falling
/// back to "no preview" for a type the user actually stores would make the
/// spacebar feel broken.
struct PreviewView: View {
    let item: ClipItem

    private var store: ClipboardStore { ClipboardStore.shared }
    private var headerColor: Color { SourceColor.color(for: item.sourceBundleID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cardBody)
        }
        .background(Theme.cardBody)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconProvider.icon(forBundleID: item.sourceBundleID))
                .resizable().interpolation(.high)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.headerText)
                    .lineLimit(1)
                Text("\(item.type.label) · \(item.createdAt.clipRelativeLong)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.headerSubText)
            }
            Spacer(minLength: 8)
            Text(metaRight)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.headerSubText)
            Text("space")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.headerSubText)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(headerColor)
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            if let img = store.loadImage(for: item) {
                // Fit, not fill: a preview must show the whole image.
                Image(nsImage: img)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
            } else {
                missing("photo", "Image data is no longer on disk")
            }

        case .color:
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: item.colorHex ?? "#000") ?? .black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(item.colorHex ?? "")
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(20)

        case .file:
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                Image(systemName: "doc.fill")
                    .font(.system(size: 54)).foregroundStyle(headerColor)
                ForEach(item.fileURLs.prefix(12), id: \.self) { u in
                    Text(URL(string: u)?.path ?? u)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                if item.fileURLs.count > 12 {
                    Text("+ \(item.fileURLs.count - 12) more")
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(24)

        case .link:
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(headerColor)
                Text(item.text ?? "")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
                Spacer(minLength: 0)
            }
            .padding(28)

        case .richText:
            // Render the real attributed text when it survived the copy.
            if let d = item.rtfData,
               let attr = NSAttributedString(rtf: d, documentAttributes: nil) {
                ScrollView {
                    Text(AttributedString(attr))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(20)
                }
            } else {
                plainText
            }

        case .text:
            plainText
        }
    }

    private var plainText: some View {
        ScrollView {
            Text(item.text ?? "")
                .font(.system(size: 13.5, design: monospaced ? .monospaced : .default))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(20)
        }
    }

    /// Code-ish text reads far better fixed-width, and most long clips here are code.
    private var monospaced: Bool {
        guard let t = item.text else { return false }
        let hints = ["{", "}", ";", "()", "=>", "def ", "func ", "import ", "const ", "  "]
        return hints.contains { t.contains($0) }
    }

    private func missing(_ symbol: String, _ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metaRight: String {
        switch item.type {
        case .text, .richText: return "\(item.charCount) characters"
        case .link:            return "Link"
        case .file:            return "\(item.fileURLs.count) file\(item.fileURLs.count == 1 ? "" : "s")"
        case .image:           return store.loadImage(for: item).map { "\(Int($0.size.width)) × \(Int($0.size.height))" } ?? "Image"
        case .color:           return item.colorHex ?? "Color"
        }
    }
}
