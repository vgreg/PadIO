//
//  CustomMenuOverlay.swift
//  PadIO
//
//  Floating NSPanel HUD for user-defined menus.
//  Opened via the "menu:<name>" action type. Navigate with dpad; A/RT = select; B/X/LT = close.
//  Two presentations, chosen by the `menu_style` config key: a vertical list (default)
//  and a circular "wheel" that can also be aimed with a thumbstick.

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
    /// How this menu is presented.
    var style: MenuStyle = .list
    /// Uniform HUD scale from the `hud_zoom` config key.
    var zoom: CGFloat = 1.0
    /// Wheel only — ring rotation in radians. Stays 0 until the dpad is used; stick
    /// aiming deliberately leaves the ring still and moves the highlight instead.
    var rotation: Double = 0

    /// Beyond this many items a wheel is unreadable, so it falls back to the list.
    static let maxWheelItems = 16

    /// The presentation actually used, after the item-count fallback.
    var effectiveStyle: MenuStyle {
        style == .wheel && labels.count > Self.maxWheelItems ? .list : style
    }

    var highlightedLabel: String? {
        guard !labels.isEmpty, labels.indices.contains(highlightedIndex) else { return nil }
        return labels[highlightedIndex]
    }

    /// Angle at which item `index` is drawn, in radians, measured clockwise from
    /// 12 o'clock. Index 0 sits at the anchor when `rotation` is 0.
    func angle(for index: Int) -> Double {
        guard !labels.isEmpty else { return 0 }
        return 2 * .pi * Double(index) / Double(labels.count) + rotation
    }

    func movePrev() {
        step(by: -1)
    }

    func moveNext() {
        step(by: 1)
    }

    /// Steps the highlight and, in wheel mode, rotates the ring so the newly
    /// highlighted item lands back on the 12 o'clock anchor.
    private func step(by delta: Int) {
        guard !labels.isEmpty else { return }
        let count = labels.count
        highlightedIndex = ((highlightedIndex + delta) % count + count) % count
        guard effectiveStyle == .wheel else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            rotation = -2 * .pi * Double(highlightedIndex) / Double(count)
        }
    }

    /// Wheel only — highlights the item nearest the direction the stick is pointing.
    /// `y` is in controller space (positive = up). Deflections below `deadzone` keep
    /// the current selection so the highlight does not jitter around centre.
    func aim(x: Float, y: Float, deadzone: Float) {
        guard effectiveStyle == .wheel, !labels.isEmpty else { return }
        guard hypot(x, y) >= deadzone else { return }

        // atan2(x, y) measures clockwise from straight up, matching `angle(for:)`.
        // Widen before the call: rounding a Float result can flip which of two
        // near-equidistant items wins.
        let stickAngle = atan2(Double(x), Double(y))
        var best = highlightedIndex
        var bestDelta = Double.greatestFiniteMagnitude
        for index in labels.indices {
            let delta = abs(Self.angularDistance(stickAngle, angle(for: index)))
            if delta < bestDelta {
                bestDelta = delta
                best = index
            }
        }
        highlightedIndex = best
    }

    /// Shortest signed distance between two angles, in radians (-pi...pi).
    private static func angularDistance(_ a: Double, _ b: Double) -> Double {
        var delta = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }
}

// MARK: - SwiftUI View

struct CustomMenuView: View {
    let viewModel: CustomMenuViewModel
    let onSelect: (Int) -> Void

    var body: some View {
        HUDZoom(zoom: viewModel.zoom) {
            switch viewModel.effectiveStyle {
            case .list:  listContent
            case .wheel: CustomMenuWheelView(viewModel: viewModel, onSelect: onSelect)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
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

    func show(
        title: String,
        labels: [String],
        style: MenuStyle = .list,
        zoom: CGFloat = 1.0,
        onSelect: @escaping (Int) -> Void
    ) {
        viewModel.title = title
        viewModel.labels = labels
        viewModel.style = style
        viewModel.zoom = zoom
        viewModel.highlightedIndex = 0
        viewModel.rotation = 0
        self.onSelect = onSelect

        if viewModel.style == .wheel && viewModel.effectiveStyle == .list {
            print("[PadIO] menu '\(title)' has \(labels.count) items, too many for the wheel — using the list")
        }

        if panel == nil { createPanel() }

        // Resize to fit the updated content (item count, style or zoom may have changed)
        if let panel, let hosting = hostingView {
            HUDPanelFitter.fit(panel: panel, hosting: hosting) { $0.center() }
        }

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
        case .dpadUp, .dpadLeft:
            viewModel.movePrev()
            return true
        case .dpadDown, .dpadRight:
            viewModel.moveNext()
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

    /// Wheel only — aims the highlight with a thumbstick. Ignored for the list style
    /// and whenever the menu is hidden, so the caller can forward unconditionally.
    func handleStick(x: Float, y: Float, deadzone: Float) {
        guard isVisible else { return }
        viewModel.aim(x: x, y: y, deadzone: deadzone)
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
            }
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
