//
//  CustomMenuOverlay.swift
//  PadIO
//
//  Floating NSPanel HUD for user-defined menus.
//  Opened via the "menu:<name>" action type. Navigate with dpad; A/RT = select; B/X/LT = close.

import AppKit
import SwiftUI
import Observation

// MARK: - View Model

@Observable
final class CustomMenuViewModel {
    /// Title shown in the header (the menu name).
    var title: String = ""
    /// Display labels for each menu item.
    var labels: [String] = []
    /// Index of the currently highlighted row.
    var highlightedIndex: Int = 0

    var highlightedLabel: String? {
        guard !labels.isEmpty, labels.indices.contains(highlightedIndex) else { return nil }
        return labels[highlightedIndex]
    }

    func moveUp() {
        guard !labels.isEmpty else { return }
        highlightedIndex = (highlightedIndex - 1 + labels.count) % labels.count
    }

    func moveDown() {
        guard !labels.isEmpty else { return }
        highlightedIndex = (highlightedIndex + 1) % labels.count
    }
}

// MARK: - SwiftUI View

struct CustomMenuView: View {
    let viewModel: CustomMenuViewModel
    let onSelect: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(viewModel.title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Divider()

            if viewModel.labels.isEmpty {
                Text("No items")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(viewModel.labels.enumerated()), id: \.offset) { index, label in
                                menuRow(label: label, isHighlighted: index == viewModel.highlightedIndex)
                                    .id(index)
                                    .onTapGesture { onSelect(index) }
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
                // Each row is ~36pt tall; cap at 10 visible rows.
                .frame(height: min(CGFloat(viewModel.labels.count) * 36 + 12, 372))
            }

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
        .frame(width: 280)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func menuRow(label: String, isHighlighted: Bool) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(isHighlighted ? .white : .primary)
            Spacer()
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

/// Manages the floating custom menu NSPanel.
@MainActor
final class CustomMenuController {
    private var panel: NSPanel?
    private let viewModel = CustomMenuViewModel()
    private var hostingView: NSHostingView<CustomMenuView>?
    /// Called with the index of the selected item when the user confirms.
    private var onSelect: ((Int) -> Void)?

    // MARK: - Show / Hide

    func show(title: String, labels: [String], onSelect: @escaping (Int) -> Void) {
        viewModel.title = title
        viewModel.labels = labels
        viewModel.highlightedIndex = 0
        self.onSelect = onSelect

        if panel == nil { createPanel() }

        // Resize to fit the updated content
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
            let index = viewModel.highlightedIndex
            if viewModel.labels.indices.contains(index) {
                let callback = onSelect
                hide()
                callback?(index)
            }
            return true
        case .b, .x, .lt:
            hide()
            return true
        default:
            // Block all other input while the menu is open
            return true
        }
    }

    // MARK: - Panel creation

    private func createPanel() {
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView]
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
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

        let view = CustomMenuView(
            viewModel: viewModel,
            onSelect: { [weak self] index in
                let callback = self?.onSelect
                self?.hide()
                callback?(index)
            },
            onCancel: { [weak self] in self?.hide() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        p.contentView = hosting

        let fittingSize = hosting.fittingSize
        p.setContentSize(fittingSize)

        self.hostingView = hosting
        self.panel = p
    }
}
