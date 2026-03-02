//
//  MappingResolver.swift
//  PadIO
//
//  Created by Vincent Grégoire on 2026-03-02.
//
//  Resolves a (button, profile, mode) triple to an Action using the loaded config.

import Foundation
import CoreGraphics

// MARK: - Action

/// An action to execute in response to a controller input.
enum Action: Sendable {
    /// Emit a synthetic keystroke.
    case keystroke(keyCode: CGKeyCode, flags: CGEventFlags)
    /// Show the mode picker overlay.
    case modeSelect
}

// MARK: - Resolver

struct MappingResolver {

    // MARK: - Profile resolution

    /// Finds the matching profile for a given bundle ID.
    ///
    /// Resolution order:
    /// 1. First profile whose `apps` list contains `bundleID`.
    /// 2. The profile named "default" (regardless of its `apps` list).
    /// 3. nil if no profile matches and no default exists.
    func resolveProfile(bundleID: String?, config: MappingConfig) -> (name: String, profile: ProfileConfig)? {
        guard let bundleID else {
            return config.profiles["default"].map { ("default", $0) }
        }
        // Explicit app match
        if let match = config.profiles.first(where: { $0.value.apps.contains(bundleID) }) {
            return (match.key, match.value)
        }
        // Fall back to default profile
        if let defaultProfile = config.profiles["default"] {
            return ("default", defaultProfile)
        }
        return nil
    }

    // MARK: - Button resolution

    /// Resolves an action for a button press given the active profile and mode.
    ///
    /// Resolution cascade:
    /// 1. Top-level config `global` bindings.
    /// 2. Profile-level `global` bindings.
    /// 3. Active mode bindings within the profile.
    func resolve(button: ButtonID, profile: ProfileConfig?, activeMode: String?, config: MappingConfig) -> Action? {
        let key = button.rawValue

        // 1. Top-level global (supersedes everything)
        if let actionConfig = config.global[key] {
            return buildAction(from: actionConfig)
        }

        guard let profile else { return nil }

        // 2. Profile-level global
        if let actionConfig = profile.global[key] {
            return buildAction(from: actionConfig)
        }

        // 3. Active mode bindings
        if let modeName = activeMode,
           let mode = profile.modes[modeName],
           let actionConfig = mode.bindings[key] {
            return buildAction(from: actionConfig)
        }

        return nil
    }

    // MARK: - Action building

    private func buildAction(from config: ActionConfig) -> Action? {
        switch config.type {
        case "keystroke":
            guard let keyName = config.key else {
                print("[PadIO] Keystroke action missing 'key'")
                return nil
            }
            guard let keyCode = Self.keyCode(for: keyName) else {
                print("[PadIO] Unknown key name: '\(keyName)'")
                return nil
            }
            let flags = Self.modifierFlags(for: config.modifiers ?? [])
            return .keystroke(keyCode: keyCode, flags: flags)

        case "mode_select":
            return .modeSelect

        default:
            print("[PadIO] Unknown action type: '\(config.type)'")
            return nil
        }
    }

    // MARK: - Key name → CGKeyCode

    static func keyCode(for name: String) -> CGKeyCode? {
        keyCodeMap[name.lowercased()]
    }

    // US keyboard virtual key codes (kVK_* constants from Carbon HIToolbox)
    private static let keyCodeMap: [String: CGKeyCode] = [
        // Letters
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03,
        "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "u": 0x20, "i": 0x22, "o": 0x1F,
        "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
        "n": 0x2D, "m": 0x2E,
        // Numbers
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C,
        "9": 0x19, "0": 0x1D,
        // Special keys
        "return": 0x24, "enter": 0x24,
        "tab": 0x30,
        "space": 0x31,
        "delete": 0x33, "backspace": 0x33,
        "escape": 0x35, "esc": 0x35,
        "forwarddelete": 0x75,
        // Arrow keys
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        // Navigation
        "pageup": 0x74, "pagedown": 0x79,
        "home": 0x73, "end": 0x77,
        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        // Punctuation
        "[": 0x21, "]": 0x1E, "\\": 0x2A,
        ";": 0x29, "'": 0x27,
        ",": 0x2B, ".": 0x2F, "/": 0x2C,
        "`": 0x32, "-": 0x1B, "=": 0x18,
    ]

    // MARK: - Modifier flags

    static func modifierFlags(for names: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for name in names {
            switch name.lowercased() {
            case "cmd", "command":   flags.insert(.maskCommand)
            case "ctrl", "control":  flags.insert(.maskControl)
            case "alt", "option":    flags.insert(.maskAlternate)
            case "shift":            flags.insert(.maskShift)
            default:
                print("[PadIO] Unknown modifier: '\(name)'")
            }
        }
        return flags
    }
}
