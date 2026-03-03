//
//  MappingConfig.swift
//  PadIO
//
//  Created by Vincent Grégoire on 2026-03-02.
//
//  Codable types for ~/.config/padio/config.json and the ConfigLoader.

import Foundation
import Combine

// MARK: - Config types

/// A single item in a custom menu.
struct MenuItemConfig: Codable, Sendable {
    /// Display label shown in the menu row.
    let label: String
    /// Action to execute when this item is selected.
    let action: ActionConfig
}

/// A named custom menu — an ordered list of label/action pairs.
/// Stored as a JSON array for clean config authoring.
struct MenuConfig: Codable, Sendable {
    let items: [MenuItemConfig]

    init(items: [MenuItemConfig]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        items = try container.decode([MenuItemConfig].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }
}

// MARK: - Haptics config

/// Top-level haptics configuration — all haptic behaviours are opt-in.
struct HapticsConfig: Codable, Sendable {
    /// Rumble on system alert sounds (the macOS "beep").
    let onSystemBeep: RumbleEventConfig?
    /// Rumble when a user notification is delivered.
    let onNotification: NotificationRumbleConfig?

    enum CodingKeys: String, CodingKey {
        case onSystemBeep     = "on_system_beep"
        case onNotification   = "on_notification"
    }

    /// Parameters for a single rumble event.
    struct RumbleEventConfig: Codable, Sendable {
        /// Motor intensity (0.0–1.0). Default 0.5.
        let intensity: Double?
        /// Haptic sharpness (0.0–1.0). Default 0.3.
        let sharpness: Double?
        /// Duration in seconds. Default 0.2.
        let duration: Double?
    }

    /// Rumble triggered by notification delivery, with optional app filter.
    struct NotificationRumbleConfig: Codable, Sendable {
        /// Motor intensity (0.0–1.0). Default 0.6.
        let intensity: Double?
        /// Haptic sharpness (0.0–1.0). Default 0.4.
        let sharpness: Double?
        /// Duration in seconds. Default 0.25.
        let duration: Double?
        /// If set, only rumble when the notification comes from one of these bundle IDs.
        /// If omitted or empty, rumble for all notifications.
        let apps: [String]?
    }
}

/// Top-level config file structure.
struct MappingConfig: Codable, Sendable {
    /// Default trigger axis threshold (0–1). Defaults to 0.5 if omitted.
    var triggerThreshold: Double?
    /// When true, shows a floating HUD on every button press with the button name and resolved action.
    /// Defaults to false when omitted. Set to true during development, false for release.
    var debugOverlay: Bool?
    /// Top-level global bindings applied before any profile lookup.
    var global: [String: ActionConfig]
    /// Named profiles, keyed by profile name (e.g. "default", "terminal").
    var profiles: [String: ProfileConfig]
    /// Named custom menus, keyed by menu name (e.g. "git", "window").
    /// Opened via the "menu:<name>" action type.
    var menus: [String: MenuConfig]
    /// Optional haptic/rumble configuration for system event triggers.
    var haptics: HapticsConfig?

    enum CodingKeys: String, CodingKey {
        case triggerThreshold = "trigger_threshold"
        case debugOverlay = "debug_overlay"
        case global
        case profiles
        case menus
        case haptics
    }

    init(triggerThreshold: Double?, debugOverlay: Bool?, global: [String: ActionConfig], profiles: [String: ProfileConfig], menus: [String: MenuConfig], haptics: HapticsConfig? = nil) {
        self.triggerThreshold = triggerThreshold
        self.debugOverlay = debugOverlay
        self.global = global
        self.profiles = profiles
        self.menus = menus
        self.haptics = haptics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        triggerThreshold = try container.decodeIfPresent(Double.self, forKey: .triggerThreshold)
        debugOverlay     = try container.decodeIfPresent(Bool.self, forKey: .debugOverlay)
        global           = try container.decodeIfPresent([String: ActionConfig].self, forKey: .global) ?? [:]
        profiles         = try container.decode([String: ProfileConfig].self, forKey: .profiles)
        menus            = try container.decodeIfPresent([String: MenuConfig].self, forKey: .menus) ?? [:]
        haptics          = try container.decodeIfPresent(HapticsConfig.self, forKey: .haptics)
    }

    static let empty = MappingConfig(triggerThreshold: nil, debugOverlay: nil, global: [:], profiles: [:], menus: [:])
}

/// A profile matches a set of apps by bundle ID and provides per-mode button mappings.
struct ProfileConfig: Codable, Sendable {
    /// Bundle IDs this profile applies to (empty list = default / catch-all).
    let apps: [String]
    /// Mode name to activate when first switching to this profile's app.
    let defaultMode: String
    /// Bindings that apply regardless of the active mode in this profile.
    let global: [String: ActionConfig]
    /// Named modes within this profile, each with their own button bindings.
    let modes: [String: ModeConfig]

    enum CodingKeys: String, CodingKey {
        case apps
        case defaultMode = "default_mode"
        case global
        case modes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps        = try container.decodeIfPresent([String].self, forKey: .apps) ?? []
        defaultMode = try container.decode(String.self, forKey: .defaultMode)
        global      = try container.decodeIfPresent([String: ActionConfig].self, forKey: .global) ?? [:]
        modes       = try container.decodeIfPresent([String: ModeConfig].self, forKey: .modes) ?? [:]
    }
}

/// A mode is a flat dictionary of button name → action config.
/// Stored as a single-value container (raw JSON object) for clean config authoring.
struct ModeConfig: Codable, Sendable {
    let bindings: [String: ActionConfig]

    init(bindings: [String: ActionConfig]) {
        self.bindings = bindings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        bindings = try container.decode([String: ActionConfig].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bindings)
    }
}

/// A single action definition in the config.
/// Using a class to allow recursive `trigger`/`steps` nesting.
final class ActionConfig: Codable, Sendable {
    /// Action type: "keystroke", "mode_select", or "sequence".
    let type: String
    /// For "keystroke": the human-readable key name (e.g. "space", "escape", "j", "play_pause").
    let key: String?
    /// For "keystroke": modifier keys (e.g. ["ctrl"], ["cmd", "shift"], ["hyper"], ["meh"]).
    let modifiers: [String]?
    /// For "sequence": ordered list of keystroke steps to fire in succession.
    let steps: [ActionConfig]?
    /// For "sequence": delay in seconds between steps. Defaults to 0.05.
    let delay: Double?
    /// For "mouse_move" / "scroll": base speed multiplier for both axes.
    let speed: Double?
    /// For "mouse_move" / "scroll": speed multiplier for the X axis (overrides `speed`).
    let xSpeed: Double?
    /// For "mouse_move" / "scroll": speed multiplier for the Y axis (overrides `speed`).
    let ySpeed: Double?
    /// For "mouse_move" / "scroll": invert the X axis.
    let xInverted: Bool?
    /// For "mouse_move" / "scroll": invert the Y axis.
    let yInverted: Bool?
    /// For "mouse_move" / "scroll": ButtonID rawValue of a button that acts as a speed modifier when held.
    let modifier: String?
    /// For "mouse_move" / "scroll": speed multiplier applied when the modifier button is held. Defaults to 2.0.
    let modifierSpeed: Double?
    /// Reserved for future dual-use: action config when button is pressed briefly.
    let trigger: ActionConfig?
    /// Reserved for future dual-use: mode name to hold while button is held.
    let hold: String?
    /// For "rumble": motor intensity (0.0–1.0). Default 0.5.
    let intensity: Double?
    /// For "rumble": haptic sharpness (0.0–1.0). Default 0.3.
    let sharpness: Double?
    // Note: `duration` is shared with "sequence" (delay between steps) and "rumble" (rumble length in seconds).

    enum CodingKeys: String, CodingKey {
        case type, key, modifiers, steps, delay
        case speed
        case xSpeed = "x_speed"
        case ySpeed = "y_speed"
        case xInverted = "x_inverted"
        case yInverted = "y_inverted"
        case modifier
        case modifierSpeed = "modifier_speed"
        case trigger, hold
        case intensity, sharpness
    }

    init(type: String, key: String? = nil, modifiers: [String]? = nil, steps: [ActionConfig]? = nil, delay: Double? = nil, speed: Double? = nil, xSpeed: Double? = nil, ySpeed: Double? = nil, xInverted: Bool? = nil, yInverted: Bool? = nil, modifier: String? = nil, modifierSpeed: Double? = nil, trigger: ActionConfig? = nil, hold: String? = nil, intensity: Double? = nil, sharpness: Double? = nil) {
        self.type = type
        self.key = key
        self.modifiers = modifiers
        self.steps = steps
        self.delay = delay
        self.speed = speed
        self.xSpeed = xSpeed
        self.ySpeed = ySpeed
        self.xInverted = xInverted
        self.yInverted = yInverted
        self.modifier = modifier
        self.modifierSpeed = modifierSpeed
        self.trigger = trigger
        self.hold = hold
        self.intensity = intensity
        self.sharpness = sharpness
    }
}

// MARK: - Config loader

/// Loads and hot-reloads the mapping config from disk.
@MainActor
final class ConfigLoader: ObservableObject {
    @Published private(set) var config: MappingConfig = .empty
    @Published private(set) var configError: String? = nil

    static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/padio/config.json"
    }()

    private var fileMonitorSource: DispatchSourceFileSystemObject?

    init() {
        loadConfig()
        setupFileMonitor()
    }

    deinit {
        fileMonitorSource?.cancel()
    }

    // MARK: - Load

    func loadConfig() {
        let path = Self.configPath
        guard FileManager.default.fileExists(atPath: path) else {
            configError = "Config not found at \(path)"
            config = .empty
            print("[PadIO] Config: \(configError!)")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            config = try JSONDecoder().decode(MappingConfig.self, from: data)
            configError = nil
            let profileNames = config.profiles.keys.sorted().joined(separator: ", ")
            print("[PadIO] Config loaded: \(config.profiles.count) profile(s): \(profileNames)")
        } catch {
            configError = "Parse error: \(error.localizedDescription)"
            config = .empty
            print("[PadIO] Config error: \(error)")
        }
    }

    // MARK: - Hot-reload via DispatchSource

    private func setupFileMonitor() {
        let path = Self.configPath
        // Open with O_EVTONLY so we don't prevent deletion/rename
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                print("[PadIO] Config file changed, reloading...")
                self?.loadConfig()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitorSource = source
    }
}
