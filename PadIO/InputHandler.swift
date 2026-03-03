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

    // MARK: - Keystroke emission

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
}
