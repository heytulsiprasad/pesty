import SwiftUI

struct BarView: View {
    @Bindable private var store = ClipboardStore.shared
    @Bindable private var settings = Settings.shared

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
            Theme.panelTint
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                topBar
                strip
            }
        }
        .clipShape(RoundedCorners(radius: Theme.cornerRadius, corners: [.topLeft, .topRight]))
        .ignoresSafeArea()
    }

    // Paste centers search + tabs across the strip. The overlay keeps the trailing
    // menu pinned without it stealing width from the centered group.
    private var topBar: some View {
        HStack(spacing: 12) {
            searchIndicator
            PinboardTabs()
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { moreMenu }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var searchIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(store.searchText.isEmpty ? Theme.textSecondary : Theme.textPrimary)
            if !store.searchText.isEmpty {
                Text(store.searchText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Button { store.searchText = ""; store.selectFirst() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, store.searchText.isEmpty ? 0 : 10)
        .frame(height: 30)
        .background(store.searchText.isEmpty ? Color.clear : Theme.fieldBG, in: Capsule())
        .animation(.easeOut(duration: 0.15), value: store.searchText.isEmpty)
    }

    private var moreMenu: some View {
        Menu {
            Button("Settings…") { AppController.shared.showSettings() }
            Button("Clear History") { store.clearHistory() }
            Divider()
            Button(settings.iCloudSync ? "Turn Off iCloud Sync" : "Turn On iCloud Sync") {
                AppController.shared.toggleICloudSync()
            }
            Divider()
            Button("About Pesty") { AppController.shared.showAbout() }
            Button("Quit Pesty") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34)
        .fixedSize()
    }

    /// One curve for everything that moves cards: promotion to the front, capture,
    /// deletion, search filtering, and the scroll that follows the selected card.
    private static let slide = Animation.spring(response: 0.45, dampingFraction: 0.85)

    private var strip: some View {
        let items = store.visibleItems
        // Keyed on identity order, not count, so a promoted card slides to the front
        // instead of snapping — a reorder leaves the count unchanged.
        let order = items.map(\.id)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.cardSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipCardView(item: item,
                                     index: index,
                                     selected: item.id == store.selectedID)
                            .id(item.id)
                            // The selected card travels over its neighbours, not under.
                            .zIndex(item.id == store.selectedID ? 1 : 0)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.92).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 18)
                .animation(Self.slide, value: order)
            }
            .onChange(of: store.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            // A promoted card keeps its id, so the selection does not change and the
            // scroll above never fires; follow it to the front here.
            .onChange(of: order) { _, _ in
                guard let id = store.selectedID else { return }
                withAnimation(Self.slide) { proxy.scrollTo(id, anchor: .center) }
            }
            .overlay { if items.isEmpty { emptyState } }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(store.searchText.isEmpty
                 ? "Nothing copied yet"
                 : "No matches for “\(store.searchText)”")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
}
