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
import Carbon
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

    // MARK: - Modifier hold / release (flagsChanged)

    /// Key codes for modifier keys used in flagsChanged events.
    private static let modifierKeyCodes: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskCommand,     0x37),  // kVK_Command
        (.maskShift,       0x38),  // kVK_Shift
        (.maskAlternate,   0x3A),  // kVK_Option
        (.maskControl,     0x3B),  // kVK_Control
        (.maskSecondaryFn, 0x3F),  // kVK_Function (Globe)
    ]

    /// Emit a flagsChanged event to press modifier keys. macOS will treat these
    /// modifiers as held until a corresponding release event is sent.
    func emitModifierDown(flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Use the key code of the first matching modifier
        let keyCode = Self.modifierKeyCodes.first(where: { flags.contains($0.flag) })?.keyCode ?? 0x37
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else { return }
        event.type = .flagsChanged
        event.flags = flags
        event.post(tap: .cgSessionEventTap)
        print("[PadIO] Emitted modifier down: flags=\(flags.rawValue)")
    }

    /// Emit a flagsChanged event to release modifier keys.
    func emitModifierUp(flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = Self.modifierKeyCodes.first(where: { flags.contains($0.flag) })?.keyCode ?? 0x37
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        event.type = .flagsChanged
        event.flags = []  // Empty flags = all modifiers released
        event.post(tap: .cgSessionEventTap)
        print("[PadIO] Emitted modifier up: flags=\(flags.rawValue)")
    }

    // MARK: - Individual key down / key up

    /// Emit only a key-down event (no matching key-up). Used for hold actions.
    func emitKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else { return }
        keyDown.flags = flags
        keyDown.post(tap: .cgSessionEventTap)
        print("[PadIO] Emitted key down: keyCode=0x\(String(keyCode, radix: 16)) flags=\(flags.rawValue)")
    }

    /// Emit only a key-up event. Used to release a held key.
    func emitKeyUp(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyUp.flags = flags
        keyUp.post(tap: .cgSessionEventTap)
        print("[PadIO] Emitted key up: keyCode=0x\(String(keyCode, radix: 16)) flags=\(flags.rawValue)")
    }

    // MARK: - Mouse down / up / drag

    /// Emit only a mouse-down event at the current cursor position.
    func emitMouseDown(button: CGMouseButton) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let pos = CGEvent(source: nil)?.location ?? .zero
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        guard let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: pos, mouseButton: button) else { return }
        down.post(tap: .cgSessionEventTap)
        print("[PadIO] Emitted mouse down: \(button == .left ? "left" : "right")")
    }

    /// Emit only a mouse-up event at the current cursor position.
    func emitMouseUp(button: CGMouseButton) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let pos = CGEvent(source: nil)?.location ?? .zero
        let upType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        guard let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: pos, mouseButton: button) else { return }
        up.post(tap: .cgSessionEventTap)
        print("[PadIO] Emitted mouse up: \(button == .left ? "left" : "right")")
    }

    /// Emit a mouse-drag event (mouse-moved while button is held).
    func emitMouseDrag(dx: CGFloat, dy: CGFloat, button: CGMouseButton) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(x: currentPos.x + dx, y: currentPos.y + dy)
        let dragType: CGEventType = button == .left ? .leftMouseDragged : .rightMouseDragged

        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: dragType,
            mouseCursorPosition: newPos,
            mouseButton: button
        ) else { return }

        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
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

    // MARK: - Keyboard Viewer

    /// Toggle the macOS Keyboard Viewer floating palette on or off.
    /// Uses the Carbon TextInputSources API — no Accessibility permission required.
    func toggleKeyboardViewer() {
        // Find the Keyboard Viewer pseudo-input-source
        let filter = [kTISPropertyInputSourceType: kTISTypeKeyboardViewer] as CFDictionary
        guard
            let cfList = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
            let sources = cfList as? [TISInputSource],
            let viewer = sources.first
        else {
            print("[PadIO] Keyboard Viewer input source not found")
            return
        }

        // Read the current selected state
        let isSelected: Bool
        if let ptr = TISGetInputSourceProperty(viewer, kTISPropertyInputSourceIsSelected) {
            isSelected = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
        } else {
            isSelected = false
        }

        if isSelected {
            TISDeselectInputSource(viewer)
            print("[PadIO] Keyboard Viewer hidden")
        } else {
            TISSelectInputSource(viewer)
            print("[PadIO] Keyboard Viewer shown")
        }
    }

    // MARK: - Input source cycling

    /// Cycle to the next enabled keyboard input source (language/layout).
    /// Uses the Carbon TextInputSources API — no Accessibility permission required.
    func cycleToNextInputSource() {
        // List all selectable keyboard input sources
        let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard
            let cfList = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
            let allSources = cfList as? [TISInputSource]
        else {
            print("[PadIO] Could not list input sources")
            return
        }

        // Keep only sources that can actually be selected (excludes keyboard viewers, etc.)
        let selectable = allSources.filter { source in
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { return false }
            return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
        }
        guard !selectable.isEmpty else { return }

        // Find the current source by comparing input source IDs
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        let currentID = TISGetInputSourceProperty(current, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }

        let currentIndex = selectable.firstIndex { source in
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            return id == currentID
        } ?? 0

        let nextSource = selectable[(currentIndex + 1) % selectable.count]
        TISSelectInputSource(nextSource)

        let nextID = TISGetInputSourceProperty(nextSource, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "unknown"
        print("[PadIO] Switched input source to: \(nextID)")
    }
}
