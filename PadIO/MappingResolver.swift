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
    /// Emit a sequence of synthetic keystrokes with a delay between each.
    case sequence(steps: [(keyCode: CGKeyCode, flags: CGEventFlags)], delay: TimeInterval)
    /// Emit a system-defined media/special key event (play/pause, volume, etc.).
    case mediaKey(keyType: Int32)
    /// Inject a unicode string directly into the frontmost app (bypasses key code mapping).
    case textInput(text: String)
    /// Show the mode picker overlay.
    case modeSelect
    /// Switch to the previous mode in the sorted list of modes for the current profile.
    case prevMode
    /// Switch to the next mode in the sorted list of modes for the current profile.
    case nextMode
    /// Switch directly to the named mode.
    case setMode(name: String)
    /// Open a named custom menu overlay.
    case openMenu(name: String)
    /// Emit a left mouse button click at the current cursor position.
    case leftClick
    /// Emit a right mouse button click at the current cursor position.
    case rightClick
    /// Toggle the macOS Keyboard Viewer floating palette.
    case keyboardViewer
    /// Cycle to the next enabled keyboard input source (language/layout).
    case nextInputSource
    /// Fire a haptic rumble on all connected controllers.
    case rumble(intensity: Double, sharpness: Double, duration: Double)
    /// Hold left mouse button down (for drag operations).
    case leftClickHold
    /// Release left mouse button.
    case leftClickRelease
    /// Hold right mouse button down.
    case rightClickHold
    /// Release right mouse button.
    case rightClickRelease
    /// Press a key down without releasing.
    case keyDown(keyCode: CGKeyCode, flags: CGEventFlags)
    /// Release a previously held key.
    case keyUp(keyCode: CGKeyCode, flags: CGEventFlags)
    /// No-op action — does nothing. Used as a tap action when only the hold behavior is wanted.
    case noop
    /// Hold modifier keys down via flagsChanged events (e.g., Cmd for app switcher).
    case modifierHold(flags: CGEventFlags)
    /// Release held modifier keys via flagsChanged events.
    case modifierRelease(flags: CGEventFlags)
}

// MARK: - Axis mapping

/// A resolved axis-to-pointer mapping derived from an ActionConfig with type "mouse_move" or "scroll".
struct AxisMapping: Sendable {
    enum Kind: Sendable { case mouseMove, scroll }
    let kind: Kind
    let xSpeed: CGFloat
    let ySpeed: CGFloat
    let xInverted: Bool
    let yInverted: Bool
    /// ButtonID of a button that, when held, applies `modifierMultiplier` to the speed.
    let modifierButton: ButtonID?
    /// Speed multiplier applied when `modifierButton` is held. Defaults to 2.0.
    let modifierMultiplier: CGFloat
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
    /// Resolution cascade (combo keys first, then plain keys):
    /// 1. Combo key in active mode bindings (highest priority).
    /// 2. Combo key in profile `global`.
    /// 3. Combo key in top-level `global` (cross-profile defaults).
    /// 4. Plain key in active mode bindings (highest priority).
    /// 5. Plain key in profile `global`.
    /// 6. Plain key in top-level `global` (cross-profile defaults).
    func resolve(button: ButtonID, heldButtons: [ButtonID: Bool] = [:], profile: ProfileConfig?, activeMode: String?, config: MappingConfig) -> Action? {
        let key = button.rawValue

        // 1–3. Try combo bindings (held modifier + pressed button) through full cascade
        for modifierID in ButtonID.allCases {
            guard modifierID != button, heldButtons[modifierID] == true else { continue }
            let comboKey = "\(modifierID.rawValue)+\(key)"

            if let profile {
                if let modeName = activeMode,
                   let mode = (profile.modes[modeName] ?? config.sharedModes?[modeName]),
                   let actionConfig = mode.bindings[comboKey] {
                    return buildAction(from: actionConfig, mappingConfig: config)
                }
                if let actionConfig = profile.global[comboKey] {
                    return buildAction(from: actionConfig, mappingConfig: config)
                }
            }
            if let actionConfig = config.global[comboKey] {
                return buildAction(from: actionConfig, mappingConfig: config)
            }
        }

        // 4. Active mode bindings (highest priority)
        if let profile, let modeName = activeMode,
           let mode = (profile.modes[modeName] ?? config.sharedModes?[modeName]),
           let actionConfig = mode.bindings[key] {
            return buildAction(from: actionConfig, mappingConfig: config)
        }

        // 5. Profile-level global
        if let profile, let actionConfig = profile.global[key] {
            return buildAction(from: actionConfig, mappingConfig: config)
        }

        // 6. Top-level global (cross-profile defaults)
        if let actionConfig = config.global[key] {
            return buildAction(from: actionConfig, mappingConfig: config)
        }

        return nil
    }

    // MARK: - Axis resolution

    /// Resolves an axis mapping for a given axis source using the same cascade as button resolution.
    ///
    /// Resolution order: active mode → profile global → top-level global.
    func resolveAxisMapping(axisID: AxisID, profile: ProfileConfig?, activeMode: String?, config: MappingConfig) -> AxisMapping? {
        let key = axisID.rawValue

        if let profile, let modeName = activeMode,
           let mode = (profile.modes[modeName] ?? config.sharedModes?[modeName]),
           let actionConfig = mode.bindings[key] {
            return buildAxisMapping(from: actionConfig)
        }

        if let profile, let actionConfig = profile.global[key] {
            return buildAxisMapping(from: actionConfig)
        }

        if let actionConfig = config.global[key] {
            return buildAxisMapping(from: actionConfig)
        }

        return nil
    }

    private func buildAxisMapping(from config: ActionConfig) -> AxisMapping? {
        let kind: AxisMapping.Kind
        let defaultSpeed: CGFloat
        switch config.type {
        case "mouse_move":
            kind = .mouseMove
            defaultSpeed = 15
        case "scroll":
            kind = .scroll
            defaultSpeed = 3
        default:
            return nil
        }
        let base = CGFloat(config.speed ?? Double(defaultSpeed))
        let xSpeed = CGFloat(config.xSpeed.map { CGFloat($0) } ?? base)
        let ySpeed = CGFloat(config.ySpeed.map { CGFloat($0) } ?? base)
        let modifierButton = config.modifier.flatMap { ButtonID(rawValue: $0) }
        let modifierMultiplier = CGFloat(config.modifierSpeed ?? 2.0)
        return AxisMapping(
            kind: kind,
            xSpeed: xSpeed,
            ySpeed: ySpeed,
            xInverted: config.xInverted ?? false,
            yInverted: config.yInverted ?? false,
            modifierButton: modifierButton,
            modifierMultiplier: modifierMultiplier
        )
    }

    // MARK: - All bindings (for Help HUD)

    /// Collects all effective bindings for the current profile/mode for display in the Help HUD.
    ///
    /// Lower-priority sources are listed first; higher-priority bindings for the same button
    /// overwrite earlier ones, so the final result reflects the actual resolution order.
    static func allBindings(
        profile: ProfileConfig?,
        activeMode: String?,
        config: MappingConfig
    ) -> [(button: String, action: String)] {
        var result: [String: String] = [:]
        let resolver = MappingResolver()

        // 3. Top-level global (lowest priority — add first so higher priority overwrites)
        for (button, actionConfig) in config.global {
            if let action = resolver.buildAction(from: actionConfig, mappingConfig: config) {
                result[button] = Self.describe(action)
            }
        }

        // 2. Profile-level global (overwrites top-level global)
        if let profile {
            for (button, actionConfig) in profile.global {
                if let action = resolver.buildAction(from: actionConfig, mappingConfig: config) {
                    result[button] = Self.describe(action)
                }
            }
        }

        // 1. Active mode bindings (highest priority — overwrites all)
        if let profile, let modeName = activeMode,
           let mode = (profile.modes[modeName] ?? config.sharedModes?[modeName]) {
            for (button, actionConfig) in mode.bindings {
                if let action = resolver.buildAction(from: actionConfig, mappingConfig: config) {
                    result[button] = Self.describe(action)
                }
            }
        }

        return result.sorted { $0.key < $1.key }.map { (button: $0.key, action: $0.value) }
    }

    // MARK: - Action building

    func buildActionPublic(from config: ActionConfig, mappingConfig: MappingConfig? = nil) -> Action? {
        buildAction(from: config, mappingConfig: mappingConfig)
    }

    /// Resolves the raw ActionConfig for a button using the same cascade as resolve(),
    /// but returns the config itself (needed to inspect the `hold` field).
    func resolveActionConfig(button: ButtonID, heldButtons: [ButtonID: Bool] = [:], profile: ProfileConfig?, activeMode: String?, config: MappingConfig) -> ActionConfig? {
        let key = button.rawValue

        for modifierID in ButtonID.allCases {
            guard modifierID != button, heldButtons[modifierID] == true else { continue }
            let comboKey = "\(modifierID.rawValue)+\(key)"
            if let profile {
                if let modeName = activeMode,
                   let mode = (profile.modes[modeName] ?? config.sharedModes?[modeName]),
                   let ac = mode.bindings[comboKey] { return ac }
                if let ac = profile.global[comboKey] { return ac }
            }
            if let ac = config.global[comboKey] { return ac }
        }
        if let profile, let modeName = activeMode,
           let mode = (profile.modes[modeName] ?? config.sharedModes?[modeName]),
           let ac = mode.bindings[key] { return ac }
        if let profile, let ac = profile.global[key] { return ac }
        if let ac = config.global[key] { return ac }
        return nil
    }

    /// Returns all matching ActionConfigs for a button across the full cascade, in priority order.
    /// Used to merge press and hold from different cascade levels.
    func resolveAllConfigs(button: ButtonID, heldButtons: [ButtonID: Bool] = [:], profile: ProfileConfig?, activeMode: String?, config: MappingConfig) -> [ActionConfig] {
        let key = button.rawValue
        var results: [ActionConfig] = []

        // Combo keys (mode → profile global → top global)
        for modifierID in ButtonID.allCases {
            guard modifierID != button, heldButtons[modifierID] == true else { continue }
            let comboKey = "\(modifierID.rawValue)+\(key)"
            if let profile {
                if let modeName = activeMode,
                   let mode = (profile.modes[modeName] ?? config.sharedModes?[modeName]),
                   let ac = mode.bindings[comboKey] { results.append(ac) }
                if let ac = profile.global[comboKey] { results.append(ac) }
            }
            if let ac = config.global[comboKey] { results.append(ac) }
        }

        // Plain keys (mode → profile global → top global)
        if let profile {
            if let modeName = activeMode,
               let mode = (profile.modes[modeName] ?? config.sharedModes?[modeName]),
               let ac = mode.bindings[key] { results.append(ac) }
            if let ac = profile.global[key] { results.append(ac) }
        }
        if let ac = config.global[key] { results.append(ac) }

        return results
    }

    private func buildAction(from config: ActionConfig, mappingConfig: MappingConfig? = nil) -> Action? {
        switch config.type {
        case "keystroke":
            guard let keyName = config.key else {
                print("[PadIO] Keystroke action missing 'key'")
                return nil
            }
            // Backtick-delimited value → unicode text injection
            // Syntax: `text` where \` = literal backtick, \\ = literal backslash
            if keyName.hasPrefix("`") && keyName.hasSuffix("`") && keyName.count >= 2 {
                let inner = String(keyName.dropFirst().dropLast())
                let text = Self.unescapeBacktickString(inner)
                return .textInput(text: text)
            }
            // Check if the key name refers to a media/special key
            if let mediaKeyType = Self.mediaKeyMap[keyName.lowercased()] {
                return .mediaKey(keyType: mediaKeyType)
            }
            guard let keyCode = Self.keyCode(for: keyName) else {
                print("[PadIO] Unknown key name: '\(keyName)'")
                return nil
            }
            let flags = Self.modifierFlags(for: config.modifiers ?? [])
            return .keystroke(keyCode: keyCode, flags: flags)

        case "sequence":
            guard let stepConfigs = config.steps, !stepConfigs.isEmpty else {
                print("[PadIO] Sequence action missing 'steps'")
                return nil
            }
            var steps: [(keyCode: CGKeyCode, flags: CGEventFlags)] = []
            for step in stepConfigs {
                guard let keyName = step.key else {
                    print("[PadIO] Sequence step missing 'key'")
                    return nil
                }
                guard let keyCode = Self.keyCode(for: keyName) else {
                    print("[PadIO] Unknown key in sequence: '\(keyName)'")
                    return nil
                }
                let flags = Self.modifierFlags(for: step.modifiers ?? [])
                steps.append((keyCode: keyCode, flags: flags))
            }
            let delay = config.delay ?? 0.05
            return .sequence(steps: steps, delay: delay)

        case "mode_select":
            return .modeSelect

        case "prev_mode":
            return .prevMode

        case "next_mode":
            return .nextMode

        case _ where config.type.hasPrefix("mode:"):
            let name = String(config.type.dropFirst("mode:".count))
            guard !name.isEmpty else {
                print("[PadIO] mode: action missing mode name")
                return nil
            }
            return .setMode(name: name)

        case "menu":
            guard let name = config.name, !name.isEmpty else {
                print("[PadIO] menu action missing 'name'")
                return nil
            }
            return .openMenu(name: name)

        case _ where config.type.hasPrefix("menu:"):
            let name = String(config.type.dropFirst("menu:".count))
            guard !name.isEmpty else {
                print("[PadIO] menu: action missing menu name")
                return nil
            }
            return .openMenu(name: name)

        case "alias":
            guard let name = config.name, !name.isEmpty else {
                print("[PadIO] alias action missing 'name'")
                return nil
            }
            guard let aliasConfig = mappingConfig?.aliases?[name] else {
                print("[PadIO] Unknown alias: '\(name)'")
                return nil
            }
            // Prevent alias chaining
            guard aliasConfig.type != "alias" else {
                print("[PadIO] Alias '\(name)' cannot reference another alias")
                return nil
            }
            return buildAction(from: aliasConfig, mappingConfig: mappingConfig)

        case "left_click":
            return .leftClick

        case "right_click":
            return .rightClick

        case "left_click_hold":
            return .leftClickHold

        case "right_click_hold":
            return .rightClickHold

        case "modifier_hold":
            let flags = Self.modifierFlags(for: config.modifiers ?? [])
            guard flags != [] else {
                print("[PadIO] modifier_hold action missing 'modifiers'")
                return nil
            }
            return .modifierHold(flags: flags)

        case "keyboard_viewer":
            return .keyboardViewer

        case "next_input_source":
            return .nextInputSource

        case "rumble":
            let intensity = config.intensity ?? 0.5
            let sharpness = config.sharpness ?? 0.3
            let duration  = config.delay     ?? 0.2  // "delay" doubles as duration for rumble
            return .rumble(intensity: intensity, sharpness: sharpness, duration: duration)

        case "none":
            return .noop

        case "mouse_move", "scroll":
            // Axis-only types; not dispatched as one-shot Actions from the button pipeline.
            return nil

        default:
            print("[PadIO] Unknown action type: '\(config.type)'")
            return nil
        }
    }

    // MARK: - Action description

    static func describe(_ action: Action) -> String {
        switch action {
        case .keystroke(let keyCode, let flags):
            return describeKeystroke(keyCode: keyCode, flags: flags)

        case .sequence(let steps, _):
            let parts = steps.map { describeKeystroke(keyCode: $0.keyCode, flags: $0.flags) }
            return "sequence: \(parts.joined(separator: " → "))"

        case .mediaKey(let keyType):
            let name = mediaKeyMap.first(where: { $0.value == keyType })?.key ?? "0x\(String(keyType, radix: 16))"
            return "media: \(name)"

        case .textInput(let text):
            // Show a truncated preview for long strings
            let preview = text.count > 20 ? String(text.prefix(20)) + "…" : text
            return "text: \(preview)"

        case .modeSelect:
            return "mode_select"

        case .prevMode:
            return "prev_mode"

        case .nextMode:
            return "next_mode"

        case .setMode(let name):
            return "mode:\(name)"

        case .openMenu(let name):
            return "menu:\(name)"

        case .leftClick:
            return "left_click"

        case .rightClick:
            return "right_click"

        case .keyboardViewer:
            return "keyboard_viewer"

        case .nextInputSource:
            return "next_input_source"

        case .rumble(let intensity, _, let duration):
            return "rumble i=\(String(format: "%.1f", intensity)) t=\(String(format: "%.2f", duration))s"

        case .leftClickHold:
            return "left_click_hold"

        case .leftClickRelease:
            return "left_click_release"

        case .rightClickHold:
            return "right_click_hold"

        case .rightClickRelease:
            return "right_click_release"

        case .keyDown(let keyCode, let flags):
            return "key_down: \(describeKeystroke(keyCode: keyCode, flags: flags))"

        case .keyUp(let keyCode, let flags):
            return "key_up: \(describeKeystroke(keyCode: keyCode, flags: flags))"

        case .noop:
            return "none"

        case .modifierHold(let flags):
            return "modifier_hold: \(describeModifiers(flags))"

        case .modifierRelease(let flags):
            return "modifier_release: \(describeModifiers(flags))"
        }
    }

    private static func describeModifiers(_ flags: CGEventFlags) -> String {
        let isHyper = flags.contains(.maskCommand) && flags.contains(.maskControl) &&
                      flags.contains(.maskAlternate) && flags.contains(.maskShift)
        let isMeh   = !flags.contains(.maskCommand) && flags.contains(.maskControl) &&
                      flags.contains(.maskAlternate) && flags.contains(.maskShift)
        if isHyper { return "hyper" }
        if isMeh   { return "meh" }

        var parts: [String] = []
        if flags.contains(.maskCommand)     { parts.append("cmd") }
        if flags.contains(.maskControl)     { parts.append("ctrl") }
        if flags.contains(.maskAlternate)   { parts.append("alt") }
        if flags.contains(.maskShift)       { parts.append("shift") }
        if flags.contains(.maskSecondaryFn) { parts.append("globe") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    private static func describeKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) -> String {
        // Reverse-look up key name for display
        let keyName = keyCodeMap.first(where: { $0.value == keyCode })?.key ?? "0x\(String(keyCode, radix: 16))"
        // Check for hyper/meh shorthands
        let isHyper = flags.contains(.maskCommand) && flags.contains(.maskControl) &&
                      flags.contains(.maskAlternate) && flags.contains(.maskShift)
        let isMeh   = !flags.contains(.maskCommand) && flags.contains(.maskControl) &&
                      flags.contains(.maskAlternate) && flags.contains(.maskShift)
        if isHyper { return "hyper+\(keyName)" }
        if isMeh   { return "meh+\(keyName)" }

        var parts: [String] = [keyName]
        if flags.contains(.maskCommand)   { parts.insert("cmd", at: 0) }
        if flags.contains(.maskControl)   { parts.insert("ctrl", at: 0) }
        if flags.contains(.maskAlternate) { parts.insert("alt", at: 0) }
        if flags.contains(.maskShift)     { parts.insert("shift", at: 0) }
        return parts.joined(separator: "+")
    }

    // MARK: - Backtick string unescaping

    /// Processes escape sequences inside a backtick-delimited unicode string.
    /// - `\`` → literal backtick
    /// - `\\` → literal backslash
    private static func unescapeBacktickString(_ raw: String) -> String {
        var result = ""
        var iterator = raw.makeIterator()
        while let ch = iterator.next() {
            if ch == "\\" {
                // Consume the next character as an escape
                if let next = iterator.next() {
                    switch next {
                    case "`":  result.append("`")
                    case "\\": result.append("\\")
                    default:
                        // Unknown escape: keep both characters
                        result.append("\\")
                        result.append(next)
                    }
                } else {
                    // Trailing backslash — keep it
                    result.append("\\")
                }
            } else {
                result.append(ch)
            }
        }
        return result
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

    // MARK: - Media key name → NX key type

    /// Maps human-readable media key names to NX system-defined key type constants.
    /// These are sent as system-defined CGEvents, not regular keystrokes.
    static let mediaKeyMap: [String: Int32] = [
        "volume_up":        0,   // NX_KEYTYPE_SOUND_UP
        "volume_down":      1,   // NX_KEYTYPE_SOUND_DOWN
        "mute":             7,   // NX_KEYTYPE_MUTE
        "play_pause":       16,  // NX_KEYTYPE_PLAY
        "next_track":       17,  // NX_KEYTYPE_NEXT
        "prev_track":       18,  // NX_KEYTYPE_PREVIOUS
        "previous_track":   18,  // alias
        "brightness_up":    21,  // NX_KEYTYPE_BRIGHTNESS_UP
        "brightness_down":  22,  // NX_KEYTYPE_BRIGHTNESS_DOWN
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
            case "hyper":
                // cmd + ctrl + alt + shift
                flags.insert(.maskCommand)
                flags.insert(.maskControl)
                flags.insert(.maskAlternate)
                flags.insert(.maskShift)
            case "meh":
                // ctrl + alt + shift (no cmd)
                flags.insert(.maskControl)
                flags.insert(.maskAlternate)
                flags.insert(.maskShift)
            case "globe", "fn":
                flags.insert(.maskSecondaryFn)
            default:
                print("[PadIO] Unknown modifier: '\(name)'")
            }
        }
        return flags
    }
}
