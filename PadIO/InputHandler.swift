//
//  InputHandler.swift
//  PadIO
//
//  Created by Vincent Grégoire on 2026-03-02.
//
//  Emits synthetic keystrokes via CGEvent and manages Accessibility permissions.

import Foundation
import CoreGraphics
import AppKit

struct InputHandler {

    // MARK: - Accessibility

    /// Returns true if the app has been granted Accessibility (AX) access.
    static func hasAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Triggers the system Accessibility permission prompt and registers the app
    /// in System Settings > Privacy & Security > Accessibility.
    /// Has no effect when running under Xcode's debugger (use the built .app instead).
    static func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Keystroke emission

    /// Emit a key-down then key-up event for the given virtual key code.
    /// `keyCode` uses Core Graphics virtual key codes (e.g. 0x31 = space).
    func emitKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard InputHandler.hasAccessibilityPermission() else {
            print("[PadIO] Accessibility permission not granted — cannot emit keystrokes.")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            print("[PadIO] Failed to create CGEvent for keyCode \(keyCode)")
            return
        }

        keyDown.flags = flags
        keyUp.flags   = flags

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        print("[PadIO] Emitted keystroke: keyCode=0x\(String(keyCode, radix: 16)) flags=\(flags.rawValue)")
    }
}
