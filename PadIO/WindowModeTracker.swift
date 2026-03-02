//
//  WindowModeTracker.swift
//  PadIO
//
//  Tracks the active mode name per CGWindowID so that each window can have
//  its own mode independently. New windows inherit the profile's default mode.

import AppKit
import CoreGraphics

@MainActor
final class WindowModeTracker {
    /// mode name keyed by window ID
    private var windowModes: [CGWindowID: String] = [:]

    // MARK: - Frontmost window ID

    /// Returns the CGWindowID of the current frontmost window, or nil.
    func frontmostWindowID() -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else {
            return nil
        }
        // Windows are returned front-to-back; find the first one that is on-screen
        // and belongs to the frontmost application.
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let frontPID = frontApp.processIdentifier

        for window in list {
            guard let pid = window[kCGWindowOwnerPID] as? pid_t, pid == frontPID else { continue }
            // Skip windows with zero bounds (hidden/minimized)
            if let bounds = window[kCGWindowBounds] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"],
               w > 0, h > 0 {
                if let windowID = window[kCGWindowNumber] as? CGWindowID {
                    return windowID
                }
            }
        }
        return nil
    }

    // MARK: - Mode access

    /// Returns the stored mode for a window, or the profile's default mode if not set.
    func mode(for windowID: CGWindowID, defaultMode: String) -> String {
        windowModes[windowID] ?? defaultMode
    }

    /// Stores the mode for a window.
    func setMode(_ mode: String, for windowID: CGWindowID) {
        windowModes[windowID] = mode
        pruneClosedWindows()
    }

    // MARK: - Cleanup

    /// Removes entries for windows that are no longer open.
    private func pruneClosedWindows() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else {
            return
        }
        let openIDs = Set(list.compactMap { $0[kCGWindowNumber] as? CGWindowID })
        windowModes = windowModes.filter { openIDs.contains($0.key) }
    }
}
