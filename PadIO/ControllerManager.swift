//
//  ControllerManager.swift
//  PadIO
//
//  Orchestrates controller discovery, profile/mode resolution, and action execution.

import Foundation
import Combine
import GameController
import CoreGraphics

@MainActor
final class ControllerManager: ObservableObject {
    @Published var connectedControllers: [GCController] = []
    /// Currently active profile name (nil if no config loaded or no profile matched).
    @Published private(set) var activeProfileName: String? = nil
    /// Currently active mode name within the active profile.
    @Published private(set) var activeModeName: String? = nil

    let appObserver           = AppObserver()
    let configLoader          = ConfigLoader()
    let accessibilityPermission = AccessibilityPermission()

    private let inputHandler    = InputHandler()
    private let mappingResolver = MappingResolver()
    private var profileModes:   [String: String] = [:]  // profileName → active mode
    private let modePicker      = ModePickerController()
    private let debugOverlay    = DebugInputController()
    private let helpOverlay     = HelpController()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Allow receiving controller input even when this app is not frontmost.
        // Without this, macOS routes input state exclusively to the frontmost app.
        GCController.shouldMonitorBackgroundEvents = true

        setupNotifications()
        GCController.startWirelessControllerDiscovery()
        for controller in GCController.controllers() {
            connectController(controller)
        }
        startPollingTimer()

        // Re-resolve profile when the frontmost app changes
        appObserver.$frontmostBundleID
            .sink { [weak self] _ in self?.refreshActiveProfile() }
            .store(in: &cancellables)

        // Re-resolve profile when config reloads
        configLoader.$config
            .sink { [weak self] _ in self?.refreshActiveProfile() }
            .store(in: &cancellables)
    }

    // MARK: - Profile resolution

    private func refreshActiveProfile() {
        let bundleID = appObserver.frontmostBundleID
        let config   = configLoader.config

        guard let (name, profile) = mappingResolver.resolveProfile(bundleID: bundleID, config: config) else {
            activeProfileName = nil
            activeModeName    = nil
            return
        }

        if name != activeProfileName {
            activeProfileName = name
            activeModeName = profile.defaultMode
        }
    }

    // MARK: - Controller connection

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            MainActor.assumeIsolated { self?.connectController(controller) }
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            MainActor.assumeIsolated { self?.disconnectController(controller) }
        }
    }

    private func connectController(_ controller: GCController) {
        guard !connectedControllers.contains(controller) else { return }
        connectedControllers.append(controller)
        print("[PadIO] Controller connected: \(controller.vendorName ?? "Unknown")")
    }

    private func disconnectController(_ controller: GCController) {
        connectedControllers.removeAll { $0 == controller }
        previousButtonStates.removeValue(forKey: ObjectIdentifier(controller))
        print("[PadIO] Controller disconnected: \(controller.vendorName ?? "Unknown")")
    }

    // MARK: - Polling

    // Previous pressed state per controller, keyed by ObjectIdentifier
    private var previousButtonStates: [ObjectIdentifier: [ButtonID: Bool]] = [:]

    private func startPollingTimer() {
        // Poll at ~60Hz — fast enough to catch quick taps
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollControllers() }
        }
    }

    private func pollControllers() {
        let threshold = Float(configLoader.config.triggerThreshold ?? 0.5)
        for controller in GCController.controllers() {
            guard let gamepad = controller.extendedGamepad else { continue }
            let id = ObjectIdentifier(controller)
            var prev = previousButtonStates[id] ?? [:]

            for buttonID in ButtonID.allCases {
                let pressed = isPressed(buttonID: buttonID, gamepad: gamepad, threshold: threshold)
                let wasPressed = prev[buttonID] ?? false
                if pressed && !wasPressed {
                    handleMappedButton(buttonID)
                }
                prev[buttonID] = pressed
            }
            previousButtonStates[id] = prev
        }
    }

    // MARK: - Input dispatch

    private func handleMappedButton(_ buttonID: ButtonID) {
        // Let the help overlay consume all input while visible
        if helpOverlay.handleButton(buttonID) {
            return
        }

        // Let the mode picker consume the input first when it is visible
        if modePicker.handleButton(buttonID) {
            return
        }

        // "menu" button always opens the help HUD
        if buttonID == .menu {
            showHelp()
            return
        }

        let config = configLoader.config
        let bundleID = appObserver.frontmostBundleID

        // Resolve which profile matches the current app
        guard let (profileName, profile) = mappingResolver.resolveProfile(bundleID: bundleID, config: config) else {
            print("[PadIO] \(buttonID.rawValue) | no profile")
            if config.debugOverlay ?? false {
                debugOverlay.show(button: buttonID.rawValue, actionDescription: "no profile")
            }
            return
        }

        // Determine the active mode for this profile
        let modeName = profileModes[profileName] ?? profile.defaultMode

        print("[PadIO] \(buttonID.rawValue) | profile: \(profileName) | mode: \(modeName)")

        guard let action = mappingResolver.resolve(
            button: buttonID,
            profile: profile,
            activeMode: modeName,
            config: config
        ) else {
            print("[PadIO] No mapping for \(buttonID.rawValue)")
            if config.debugOverlay ?? false {
                debugOverlay.show(button: buttonID.rawValue, actionDescription: "no mapping")
            }
            return
        }

        if config.debugOverlay ?? false {
            debugOverlay.show(button: buttonID.rawValue, actionDescription: MappingResolver.describe(action))
        }
        executeAction(action, profile: profile, profileName: profileName, currentMode: modeName)
    }

    private func showHelp() {
        let config = configLoader.config
        let bundleID = appObserver.frontmostBundleID

        let profileResult = mappingResolver.resolveProfile(bundleID: bundleID, config: config)
        let profileName = profileResult?.name ?? "none"
        let profile = profileResult?.profile

        // Determine the active mode for this profile
        let modeName: String
        if let profileResult {
            modeName = profileModes[profileResult.name] ?? profileResult.profile.defaultMode
        } else {
            modeName = "none"
        }

        let entries = MappingResolver.allBindings(
            profile: profile,
            activeMode: modeName,
            config: config
        )

        helpOverlay.show(profileName: profileName, modeName: modeName, entries: entries)
    }

    private func executeAction(
        _ action: Action,
        profile: ProfileConfig,
        profileName: String,
        currentMode: String
    ) {
        switch action {
        case .keystroke(let keyCode, let flags):
            guard accessibilityPermission.isGranted else {
                print("[PadIO] Accessibility permission not granted — cannot emit keystrokes.")
                return
            }
            inputHandler.emitKeystroke(keyCode: keyCode, flags: flags)

        case .sequence(let steps, let delay):
            guard accessibilityPermission.isGranted else {
                print("[PadIO] Accessibility permission not granted — cannot emit keystrokes.")
                return
            }
            inputHandler.emitSequence(steps: steps, delay: delay)

        case .mediaKey(let keyType):
            // Media keys do not require Accessibility permission
            inputHandler.emitMediaKey(keyType: keyType)

        case .modeSelect:
            let modes = Array(profile.modes.keys.sorted())
            guard !modes.isEmpty else { return }
            modePicker.show(modes: modes, currentMode: currentMode) { [weak self] selectedMode in
                guard let self else { return }
                self.profileModes[profileName] = selectedMode
                self.activeModeName = selectedMode
                print("[PadIO] Mode changed to '\(selectedMode)' in profile '\(profileName)'")
            }
        }
    }

    // MARK: - Press detection

    private func isPressed(buttonID: ButtonID, gamepad: GCExtendedGamepad, threshold: Float = 0.5) -> Bool {
        switch buttonID {
        case .a:         return gamepad.buttonA.isPressed
        case .b:         return gamepad.buttonB.isPressed
        case .x:         return gamepad.buttonX.isPressed
        case .y:         return gamepad.buttonY.isPressed
        case .lb:        return gamepad.leftShoulder.isPressed
        case .rb:        return gamepad.rightShoulder.isPressed
        case .lt:        return gamepad.leftTrigger.value >= threshold
        case .rt:        return gamepad.rightTrigger.value >= threshold
        case .dpadUp:    return gamepad.dpad.up.isPressed
        case .dpadDown:  return gamepad.dpad.down.isPressed
        case .dpadLeft:  return gamepad.dpad.left.isPressed
        case .dpadRight: return gamepad.dpad.right.isPressed
        case .l3:        return gamepad.leftThumbstickButton?.isPressed == true
        case .r3:        return gamepad.rightThumbstickButton?.isPressed == true
        case .menu:      return gamepad.buttonMenu.isPressed
        case .options:   return gamepad.buttonOptions?.isPressed == true
        default:         return false
        }
    }
}
