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
    var selectedIndex: Int = 0

    var selectedMode: String? {
        guard !modes.isEmpty, modes.indices.contains(selectedIndex) else { return nil }
        return modes[selectedIndex]
    }

    func moveUp() {
        guard !modes.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + modes.count) % modes.count
    }

    func moveDown() {
        guard !modes.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % modes.count
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
                            modeRow(mode: mode, isSelected: index == viewModel.selectedIndex)
                                .id(index)
                                .onTapGesture {
                                    onConfirm(mode)
                                }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
                .onChange(of: viewModel.selectedIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 260)

            Divider()

            // Hint row
            HStack(spacing: 16) {
                hintLabel(icon: "arrowkeys", text: "Navigate")
                hintLabel(icon: "a.circle", text: "Select")
                hintLabel(icon: "x.circle", text: "Cancel")
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
    private func modeRow(mode: String, isSelected: Bool) -> some View {
        HStack {
            Text(mode)
                .font(.body)
                .foregroundStyle(isSelected ? .white : .primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
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
        viewModel.selectedIndex = modes.firstIndex(of: currentMode ?? "") ?? 0
        self.onSelect = onSelect

        if panel == nil {
            createPanel()
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
            if let mode = viewModel.selectedMode {
                let callback = onSelect
                hide()
                callback?(mode)
            }
            return true
        case .x, .lt:
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
