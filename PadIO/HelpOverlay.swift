//
//  HelpOverlay.swift
//  PadIO
//
//  Floating NSPanel HUD showing all button mappings for the current profile/mode.
//  Triggered by the "menu" button. Navigate with dpad; close with B, X, or LT.

import AppKit
import SwiftUI
import Observation

// MARK: - View Model

@Observable
final class HelpViewModel {
    var profileName: String = ""
    var modeName: String = ""
    /// Sorted list of (button, action description) pairs.
    var entries: [(button: String, action: String)] = []
    /// Currently highlighted row index for dpad scrolling.
    var highlightedIndex: Int = 0

    func scrollUp() {
        guard !entries.isEmpty else { return }
        highlightedIndex = max(0, highlightedIndex - 1)
    }

    func scrollDown() {
        guard !entries.isEmpty else { return }
        highlightedIndex = min(entries.count - 1, highlightedIndex + 1)
    }
}

// MARK: - SwiftUI View

struct HelpView: View {
    let viewModel: HelpViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 2) {
                Text("\(viewModel.profileName) · \(viewModel.modeName)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Button Mappings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            // Binding list
            if viewModel.entries.isEmpty {
                Text("No bindings defined")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(viewModel.entries.enumerated()), id: \.offset) { index, entry in
                                bindingRow(
                                    button: entry.button,
                                    action: entry.action,
                                    isHighlighted: index == viewModel.highlightedIndex
                                )
                                .id(index)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: viewModel.highlightedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Hint row
            HStack(spacing: 16) {
                hintLabel(icon: "arrowkeys", text: "Scroll")
                hintLabel(icon: "b.circle", text: "Close")
            }
            .padding(.vertical, 8)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func bindingRow(button: String, action: String, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Text(button)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(isHighlighted ? .white : .primary)
                .frame(width: 90, alignment: .leading)
            Text(action)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isHighlighted ? .white.opacity(0.85) : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : Color.clear)
        )
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

/// Manages the floating Help NSPanel. Triggered by the menu button.
@MainActor
final class HelpController {
    private var panel: NSPanel?
    private let viewModel = HelpViewModel()

    // MARK: - Show / Hide

    func show(profileName: String, modeName: String, entries: [(button: String, action: String)]) {
        viewModel.profileName = profileName
        viewModel.modeName = modeName
        viewModel.entries = entries
        viewModel.highlightedIndex = 0

        if panel == nil { createPanel() }

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
            viewModel.scrollUp()
            return true
        case .dpadDown:
            viewModel.scrollDown()
            return true
        case .b, .x, .lt, .menu:
            hide()
            return true
        default:
            // All other buttons are blocked while the help overlay is visible
            return true
        }
    }

    // MARK: - Panel creation

    private func createPanel() {
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView]
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
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

        let view = HelpView(viewModel: viewModel, onClose: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        p.contentView = hosting

        let fittingSize = hosting.fittingSize
        p.setContentSize(fittingSize)

        panel = p
    }
}
