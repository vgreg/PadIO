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

        // Re-check on any app switch — the user may have just granted permission
        // in System Settings and switched to another app. PadIO itself is never
        // frontmost during normal use, so filtering to our own bundle ID would
        // mean the re-check never fires.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
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
        _ = CGRequestPostEventAccess()
        recheck()
    }

    private static func check() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
        let axTrusted = AXIsProcessTrustedWithOptions(options)
        let postAccess = CGPreflightPostEventAccess()
        print("[PadIO] Permission check — AXTrusted=\(axTrusted) postEventAccess=\(postAccess)")
        return axTrusted
    }
}

// MARK: - Keystroke emitter

struct InputHandler {

    // MARK: - Single keystroke

    /// Emit a key-down then key-up event for the given virtual key code.
    /// `keyCode` uses Core Graphics virtual key codes (e.g. 0x31 = space).
    func emitKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let trusted = CGPreflightPostEventAccess()
        let source = CGEventSource(stateID: .combinedSessionState)
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

        print("[PadIO] Emitted keystroke: keyCode=0x\(String(keyCode, radix: 16)) flags=\(flags.rawValue) (postEventAccess=\(trusted))")
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

    // MARK: - Unicode text injection

    /// Inject a unicode string into the frontmost app using CGEvent unicode string support.
    /// This bypasses the key code → character mapping entirely, allowing any Unicode text
    /// (accents, emoji, CJK, multi-character strings) to be typed regardless of keyboard layout.
    ///
    /// The text is sent as a single key-down/key-up pair with the full UTF-16 string attached,
    /// which most text-input-aware apps (terminals, editors, text fields) handle correctly.
    func emitText(_ text: String) {
        guard !text.isEmpty else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        // Virtual key code 0 is used as a placeholder; the unicode string takes precedence.
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            print("[PadIO] Failed to create CGEvent for text input")
            return
        }

        var utf16 = Array(text.utf16)
        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        print("[PadIO] Emitted text: \(text)")
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

    // MARK: - Mouse movement

    /// Move the mouse cursor by the given pixel delta relative to its current position.
    func emitMouseMove(dx: CGFloat, dy: CGFloat) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Get current cursor position via a dummy move event
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(x: currentPos.x + dx, y: currentPos.y + dy)

        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: newPos,
            mouseButton: .left
        ) else { return }

        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        event.post(tap: .cgSessionEventTap)
    }

    // MARK: - Scroll wheel

    /// Emit a scroll wheel event with the given pixel deltas.
    /// `dy` is vertical (positive = scroll up), `dx` is horizontal (positive = scroll right).
    func emitScroll(dx: CGFloat, dy: CGFloat) {
        // CGEvent scroll wheel uses Int32 pixel values; clamp to reasonable range
        let wheel1 = Int32(exactly: Int(dy.rounded())) ?? (dy > 0 ? Int32.max : Int32.min)
        let wheel2 = Int32(exactly: Int(dx.rounded())) ?? (dx > 0 ? Int32.max : Int32.min)

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheel1,
            wheel2: wheel2,
            wheel3: 0
        ) else { return }

        event.post(tap: .cgSessionEventTap)
    }

    // MARK: - Mouse click

    /// Emit a mouse button down + up at the current cursor position.
    func emitMouseClick(button: CGMouseButton) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let pos = CGEvent(source: nil)?.location ?? .zero
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType:   CGEventType = button == .left ? .leftMouseUp   : .rightMouseUp

        guard
            let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: pos, mouseButton: button),
            let up   = CGEvent(mouseEventSource: source, mouseType: upType,   mouseCursorPosition: pos, mouseButton: button)
        else { return }

        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)

        print("[PadIO] Emitted mouse click: \(button == .left ? "left" : "right")")
    }
}
