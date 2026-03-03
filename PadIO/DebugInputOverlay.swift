//
//  DebugInputOverlay.swift
//  PadIO
//
//  Floating debug HUD showing the last button press and its resolved action.
//  Controlled by ControllerManager.debugOverlayEnabled — set to false for release.

import AppKit
import SwiftUI
import Observation

// MARK: - View Model

@Observable
final class DebugInputViewModel {
    var buttonName: String = ""
    var actionDescription: String = ""
}

// MARK: - SwiftUI View

struct DebugInputView: View {
    let viewModel: DebugInputViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(viewModel.buttonName)
                .font(.system(size: 51, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)
            Text(viewModel.actionDescription)
                .font(.system(size: 36, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 30)
        .fixedSize()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1.5)
        )
    }
}

// MARK: - Controller

@MainActor
final class DebugInputController {
    private var panel: NSPanel?
    private let viewModel = DebugInputViewModel()
    private var dismissWork: DispatchWorkItem?

    // MARK: - Show

    func show(button: String, actionDescription: String, postEventAccess: Bool = true) {
        viewModel.buttonName = button
        viewModel.actionDescription = actionDescription

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
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

        let hosting = NSHostingView(rootView: DebugInputView(viewModel: viewModel))
        p.contentView = hosting
        p.setContentSize(hosting.fittingSize)

        panel = p
    }

    private func repositionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        // Flush pending layout so fittingSize reflects the new content
        if let hosting = panel.contentView as? NSHostingView<DebugInputView> {
            hosting.layoutSubtreeIfNeeded()
            panel.setContentSize(hosting.fittingSize)
        }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.minY + 120  // 120pt above the Dock/bottom edge
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
