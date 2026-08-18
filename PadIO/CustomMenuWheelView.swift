//
//  CustomMenuWheelView.swift
//  PadIO
//
//  Circular ("donut") presentation for custom menus, selected with `"style": "wheel"`.
//  Items sit on a ring around a hub that spells out the current selection.
//
//  Two ways to drive it, both live at once:
//    - a thumbstick aims: the ring stays still and the highlight follows the stick
//    - dpad left/right rotates: the ring turns and the highlight stays on the
//      12 o'clock anchor marker

import SwiftUI

struct CustomMenuWheelView: View {
    let viewModel: CustomMenuViewModel
    let onSelect: (Int) -> Void

    // MARK: - Geometry

    /// Widest a single item chip may draw before its label truncates.
    private static let chipMaxWidth: CGFloat = 120
    /// Vertical room one chip occupies on the ring, used to keep chips from colliding.
    private static let chipPitch: CGFloat = 36
    /// Breathing room between the outermost chip edge and the panel edge.
    private static let outerPadding: CGFloat = 20

    /// Ring radius. Grows with the item count so chips never overlap, with a floor that
    /// leaves the hub enough room to sit clear of the chips at 3 and 9 o'clock.
    private var radius: CGFloat {
        let needed = CGFloat(viewModel.labels.count) * Self.chipPitch / (2 * .pi) + 60
        return max(165, needed)
    }

    /// The panel is square: the ring plus half a chip on each side, plus padding.
    private var side: CGFloat {
        2 * radius + Self.chipMaxWidth + 2 * Self.outerPadding
    }

    /// Clear space inside the ring, available to the hub. The inset keeps the hub from
    /// butting up against the chips on either side.
    private var hubWidth: CGFloat {
        2 * (radius - Self.chipMaxWidth / 2) - 40
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))

            // Faint guide showing the path the items travel along.
            Circle()
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                .frame(width: radius * 2, height: radius * 2)

            anchorMarker
            hub

            ForEach(Array(viewModel.labels.enumerated()), id: \.offset) { index, label in
                chip(label: label, isHighlighted: index == viewModel.highlightedIndex)
                    .position(position(for: index))
                    .onTapGesture { onSelect(index) }
            }
        }
        .frame(width: side, height: side)
    }

    // MARK: - Pieces

    /// Centre of item `index`, in the square's coordinate space.
    private func position(for index: Int) -> CGPoint {
        let angle = viewModel.angle(for: index)
        let centre = side / 2
        // Angles run clockwise from 12 o'clock; the view's y axis points down.
        return CGPoint(
            x: centre + radius * CGFloat(sin(angle)),
            y: centre - radius * CGFloat(cos(angle))
        )
    }

    /// Fixed selection slot at 12 o'clock — where dpad rotation brings items.
    private var anchorMarker: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .position(
                x: side / 2,
                y: side / 2 - radius - Self.chipPitch / 2 - 6
            )
    }

    /// Centre of the donut — menu name over the full label of the current selection.
    private var hub: some View {
        VStack(spacing: 6) {
            Text(viewModel.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(viewModel.highlightedLabel ?? "No items")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                hintLabel(icon: "l.joystick", text: "Aim")
                hintLabel(icon: "arrow.left.and.right", text: "Rotate")
                hintLabel(icon: "a.circle", text: "Select")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
        .frame(width: hubWidth)
    }

    private func chip(label: String, isHighlighted: Bool) -> some View {
        Text(label)
            .font(.body)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isHighlighted ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: Self.chipMaxWidth)
            .background(
                Capsule().fill(isHighlighted ? Color.accentColor : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(.separator, lineWidth: isHighlighted ? 0 : 0.5)
            )
            .contentShape(Capsule())
    }

    private func hintLabel(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
    }
}
