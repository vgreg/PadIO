//
//  ModePickerOverlay.swift
//  PadIO
//
//  Floating NSPanel HUD for selecting a mode via dpad/buttons.
//  Does not steal focus from the active terminal/app.

import AppKit
import SwiftUI
import Observation

// MARK: - View Model

@Observable
final class ModePickerViewModel {
    var modes: [String] = []
    /// Index of the currently highlighted (navigated-to) row.
    var highlightedIndex: Int = 0
    /// The mode that is already active (shown with a checkmark).
    var activeMode: String = ""

    var highlightedMode: String? {
        guard !modes.isEmpty, modes.indices.contains(highlightedIndex) else { return nil }
        return modes[highlightedIndex]
    }

    func moveUp() {
        guard !modes.isEmpty else { return }
        highlightedIndex = (highlightedIndex - 1 + modes.count) % modes.count
    }

    func moveDown() {
        guard !modes.isEmpty else { return }
        highlightedIndex = (highlightedIndex + 1) % modes.count
    }
}

// MARK: - SwiftUI View

struct ModePickerView: View {
    let viewModel: ModePickerViewModel
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Select Mode")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(viewModel.modes.enumerated()), id: \.offset) { index, mode in
                            modeRow(
                                mode: mode,
                                isHighlighted: index == viewModel.highlightedIndex,
                                isActive: mode == viewModel.activeMode
                            )
                            .id(index)
                            .onTapGesture {
                                onConfirm(mode)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
                .onChange(of: viewModel.highlightedIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            // Each row is ~36pt tall (7pt padding × 2 + ~22pt text) plus 6pt top/bottom list padding.
            // Cap at 10 visible rows; beyond that the scroll view handles navigation.
            .frame(height: min(CGFloat(viewModel.modes.count) * 36 + 12, 372))

            Divider()

            // Hint row
            HStack(spacing: 16) {
                hintLabel(icon: "arrowkeys", text: "Navigate")
                hintLabel(icon: "a.circle", text: "Select")
                hintLabel(icon: "b.circle", text: "Cancel")
            }
            .padding(.vertical, 8)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(width: 240)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func modeRow(mode: String, isHighlighted: Bool, isActive: Bool) -> some View {
        HStack {
            Text(mode)
                .font(.body)
                .foregroundStyle(isHighlighted ? .white : .primary)
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(isHighlighted ? .white : Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func hintLabel(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
    }
}

// MARK: - Controller

/// Manages the floating NSPanel. Call `show(...)` to display, `hide()` to dismiss.
@MainActor
final class ModePickerController {
    private var panel: NSPanel?
    private let viewModel = ModePickerViewModel()
    private var onSelect: ((String) -> Void)?
    private var hostingView: NSHostingView<ModePickerView>?

    // MARK: - Show / Hide

    func show(modes: [String], currentMode: String?, onSelect: @escaping (String) -> Void) {
        // Update view model
        viewModel.modes = modes
        viewModel.activeMode = currentMode ?? ""
        viewModel.highlightedIndex = modes.firstIndex(of: currentMode ?? "") ?? 0
        self.onSelect = onSelect

        if panel == nil {
            createPanel()
        }

        // Resize to fit the updated content (mode count may have changed)
        if let hosting = hostingView {
            panel?.setContentSize(hosting.fittingSize)
        }

        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Button handling

    /// Returns `true` if the button was consumed by the overlay.
    func handleButton(_ buttonID: ButtonID) -> Bool {
        guard isVisible else { return false }

        switch buttonID {
        case .dpadUp:
            viewModel.moveUp()
            return true
        case .dpadDown:
            viewModel.moveDown()
            return true
        case .a, .rt:
            if let mode = viewModel.highlightedMode {
                let callback = onSelect
                hide()
                callback?(mode)
            }
            return true
        case .b, .x, .lt:
            hide()
            return true
        default:
            return false
        }
    }

    // MARK: - Panel creation

    private func createPanel() {
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView]
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
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

        let view = ModePickerView(
            viewModel: viewModel,
            onConfirm: { [weak self] mode in
                let callback = self?.onSelect
                self?.hide()
                callback?(mode)
            },
            onCancel: { [weak self] in self?.hide() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        p.contentView = hosting

        // Size to fit
        let fittingSize = hosting.fittingSize
        p.setContentSize(fittingSize)

        self.hostingView = hosting
        self.panel = p
    }
}
