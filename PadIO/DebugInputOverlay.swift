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
        VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.buttonName)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(.primary)
            Text(viewModel.actionDescription)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
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

    func show(button: String, actionDescription: String) {
        viewModel.buttonName = button
        viewModel.actionDescription = actionDescription

        if panel == nil { createPanel() }
        repositionPanel()
        panel?.orderFrontRegardless()

        // Cancel any pending auto-dismiss and schedule a fresh one
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    func hide() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
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
        // Resize to fit current content first
        if let hosting = panel.contentView as? NSHostingView<DebugInputView> {
            panel.setContentSize(hosting.fittingSize)
        }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.minY + 40  // 40pt above the Dock/bottom edge
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
