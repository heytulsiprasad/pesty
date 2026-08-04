import AppKit
import SwiftUI

/// Quick Look-style overlay for the selected clip. A separate panel rather than an
/// overlay inside the strip: the strip is only barHeight tall, which is not enough
/// room to be worth calling a preview.
@MainActor
final class PreviewWindowController: NSWindowController, NSWindowDelegate {

    private var hosting: NSHostingView<PreviewView>?

    init() {
        let panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        // Above the strip, which sits at .modalPanel.
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.appearance = NSAppearance(named: .aqua)
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    var isOpen: Bool { window?.isVisible == true }

    func show(item: ClipItem) {
        guard let panel = window,
              let screen = BarWindowController.targetScreen() else { return }
        let vf = screen.visibleFrame

        // Roughly Quick Look's proportions, clamped so it always fits the display.
        let w = min(max(vf.width * 0.55, 520), vf.width - 80)
        let h = min(max(vf.height * 0.62, 380), vf.height - 80)
        let barH = CGFloat(Settings.shared.barHeight)
        // Sit above the strip, centred in what is left of the screen.
        let available = vf.height - barH
        let y = vf.minY + barH + max((available - h) / 2, 20)
        let frame = NSRect(x: vf.minX + (vf.width - w) / 2,
                           y: min(y, vf.maxY - h - 20),
                           width: w, height: h)

        let view = NSHostingView(rootView: PreviewView(item: item))
        panel.contentView = view
        hosting = view
        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = window, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.11
            panel.animator().alphaValue = 0
        }, completionHandler: {
            DispatchQueue.main.async {
                panel.orderOut(nil)
                // Drop the hosted view so a large image is not retained while closed.
                panel.contentView = nil
            }
        })
        hosting = nil
    }
}
