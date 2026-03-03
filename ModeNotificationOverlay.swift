//
//  ModeNotificationOverlay.swift
//  PadIO
//
//  Floating HUD displayed near the top center of the screen when the active mode changes.
//  Shows the new mode name and auto-dismisses after 1.5 seconds.

import AppKit
import SwiftUI
import Observation

// MARK: - View Model

@Observable
final class ModeNotificationViewModel {
    var modeName: String = ""
}

// MARK: - SwiftUI View

struct ModeNotificationView: View {
    let viewModel: ModeNotificationViewModel

    var body: some View {
        Text(viewModel.modeName)
            .font(.system(size: 36, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .fixedSize()
            .padding(.horizontal, 36)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1.5)
            )
    }
}

// MARK: - Controller

@MainActor
final class ModeNotificationController {
    private var panel: NSPanel?
    private let viewModel = ModeNotificationViewModel()
    private var dismissWork: DispatchWorkItem?

    // MARK: - Show

    func show(modeName: String) {
        viewModel.modeName = modeName

        if panel == nil { createPanel() }

        // Cancel any in-flight fade and snap alpha back before reshowing
        dismissWork?.cancel()
        panel?.alphaValue = 1

        repositionPanel()
        panel?.orderFrontRegardless()

        // Schedule auto-dismiss with fade-out
        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func hide() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.alphaValue = 1
        panel?.orderOut(nil)
    }

    private func fadeOut() {
        dismissWork = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel?.orderOut(nil)
                self?.panel?.alphaValue = 1
            }
        })
    }

    // MARK: - Panel creation

    private func createPanel() {
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView]
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false

        let hosting = NSHostingView(rootView: ModeNotificationView(viewModel: viewModel))
        p.contentView = hosting
        p.setContentSize(hosting.fittingSize)

        panel = p
    }

    private func repositionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        // Flush pending layout so fittingSize reflects the new content
        if let hosting = panel.contentView as? NSHostingView<ModeNotificationView> {
            hosting.layoutSubtreeIfNeeded()
            panel.setContentSize(hosting.fittingSize)
        }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        // Position near top center — 120pt below the menu bar
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height - 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
