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
import Combine

// MARK: - Permission tracker

/// Tracks Accessibility permission state without polling on every SwiftUI redraw.
/// Checks once at init, once when the app becomes active, and on explicit request.
@MainActor
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isGranted: Bool = false

    private var observer: NSObjectProtocol?

    init() {
        isGranted = Self.check()

        // Re-check whenever the app comes back to the foreground (e.g. after
        // the user grants permission in System Settings and switches back).
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.recheck() }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func recheck() {
        isGranted = Self.check()
    }

    /// Triggers the system prompt and rechecks. Call from the menu "Grant Access" button.
    func request() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
        recheck()
    }

    private static func check() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
        return AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - Keystroke emitter

struct InputHandler {

    // MARK: - Single keystroke

    /// Emit a key-down then key-up event for the given virtual key code.
    /// `keyCode` uses Core Graphics virtual key codes (e.g. 0x31 = space).
    func emitKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
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

    // MARK: - Key sequence

    /// Emit a sequence of keystrokes with a configurable delay between each step.
    /// Blocks the calling thread between steps using `usleep` — call from a background context
    /// if the delay is significant, but the default 50ms is imperceptible on the main thread.
    func emitSequence(steps: [(keyCode: CGKeyCode, flags: CGEventFlags)], delay: TimeInterval) {
        for (index, step) in steps.enumerated() {
            emitKeystroke(keyCode: step.keyCode, flags: step.flags)
            if index < steps.count - 1 {
                usleep(UInt32(delay * 1_000_000))
            }
        }
    }

    // MARK: - Media/special keys

    /// Emit a media/special key event (play/pause, volume, brightness, etc.)
    /// using NX system-defined events. These bypass the normal keystroke path and
    /// are handled by the media key daemon / Now Playing infrastructure.
    ///
    /// `keyType` corresponds to NX_KEYTYPE_* constants (e.g. NX_KEYTYPE_PLAY = 16).
    func emitMediaKey(keyType: Int32) {
        // NX system-defined events encode the key type and state in the data1 field:
        //   bits 31–16: key type
        //   bits 15–8:  key flags (0x0A = key down, 0x0B = key up)
        //   bits 7–0:   repeat count (0 for non-repeating)
        let keyDown: Int = (Int(keyType) << 16) | (0x0A << 8)
        let keyUp:   Int = (Int(keyType) << 16) | (0x0B << 8)

        func postEvent(data1: Int) {
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,   // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: data1,
                data2: -1
            ) else { return }
            event.cgEvent?.post(tap: .cgSessionEventTap)
        }

        postEvent(data1: keyDown)
        postEvent(data1: keyUp)

        print("[PadIO] Emitted media key: keyType=\(keyType)")
    }
}
