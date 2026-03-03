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

    /// Set to false before release to disable the debug input HUD.
    static let debugOverlayEnabled = true

    private let inputHandler    = InputHandler()
    private let mappingResolver = MappingResolver()
    private var profileModes:   [String: String] = [:]  // profileName → active mode
    private let modePicker      = ModePickerController()
    private let debugOverlay    = DebugInputController()

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupNotifications()
        GCController.startWirelessControllerDiscovery()
        for controller in GCController.controllers() {
            connectController(controller)
        }

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

        // Update profile name; mode will be resolved lazily on next button press
        // (avoids calling CGWindowListCopyWindowInfo on the main thread here)
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
            Task { @MainActor [weak self] in self?.connectController(controller) }
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            Task { @MainActor [weak self] in self?.disconnectController(controller) }
        }
    }

    private func connectController(_ controller: GCController) {
        guard !connectedControllers.contains(controller) else { return }
        connectedControllers.append(controller)
        print("[PadIO] Controller connected: \(controller.vendorName ?? "Unknown")")
        setupInputHandlers(for: controller)
    }

    private func disconnectController(_ controller: GCController) {
        connectedControllers.removeAll { $0 == controller }
        print("[PadIO] Controller disconnected: \(controller.vendorName ?? "Unknown")")
    }

    // MARK: - Input handler registration

    private func setupInputHandlers(for controller: GCController) {
        guard let gamepad = controller.extendedGamepad else {
            print("[PadIO] No extendedGamepad profile, skipping input setup.")
            return
        }

        // All standard elements
        gamepad.valueChangedHandler = { [weak self] (profile: GCExtendedGamepad, element: GCControllerElement) in
            Task { @MainActor [weak self] in
                self?.handleElement(element, gamepad: profile, controller: controller)
            }
        }

        // Xbox-specific buttons (share, paddles) are on a separate profile
        if let xbox = controller.physicalInputProfile as? GCXboxGamepad {
            let xboxHandler = { [weak self] (btn: GCControllerButtonInput, _: Float, pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let id = ButtonIdentifier.identifyXbox(element: btn, xbox: xbox) {
                        self.handleMappedButton(id)
                    }
                }
            }
            xbox.buttonShare?.valueChangedHandler   = xboxHandler
            xbox.paddleButton1?.valueChangedHandler = xboxHandler
            xbox.paddleButton2?.valueChangedHandler = xboxHandler
            xbox.paddleButton3?.valueChangedHandler = xboxHandler
            xbox.paddleButton4?.valueChangedHandler = xboxHandler
        }
    }

    // MARK: - Input dispatch

    private func handleElement(_ element: GCControllerElement, gamepad: GCExtendedGamepad, controller: GCController) {
        guard let buttonID = ButtonIdentifier.identify(element: element, gamepad: gamepad) else {
            return // analog axis or unrecognized element
        }

        let threshold = Float(configLoader.config.triggerThreshold ?? 0.5)

        // For triggers: only fire when crossing the threshold (press, not release)
        switch buttonID {
        case .lt:
            guard gamepad.leftTrigger.value >= threshold else { return }
        case .rt:
            guard gamepad.rightTrigger.value >= threshold else { return }
        default:
            // For all other buttons: only fire on press, not release
            guard isPressed(buttonID: buttonID, gamepad: gamepad) else { return }
        }

        handleMappedButton(buttonID)
    }

    private func handleMappedButton(_ buttonID: ButtonID) {
        // Let the mode picker consume the input first when it is visible
        if modePicker.handleButton(buttonID) {
            return
        }

        let config = configLoader.config
        let bundleID = appObserver.frontmostBundleID

        // Resolve which profile matches the current app
        guard let (profileName, profile) = mappingResolver.resolveProfile(bundleID: bundleID, config: config) else {
            print("[PadIO] \(buttonID.rawValue) | no profile")
            if Self.debugOverlayEnabled {
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
            if Self.debugOverlayEnabled {
                debugOverlay.show(button: buttonID.rawValue, actionDescription: "no mapping")
            }
            return
        }

        if Self.debugOverlayEnabled {
            debugOverlay.show(button: buttonID.rawValue, actionDescription: MappingResolver.describe(action))
        }
        executeAction(action, profile: profile, profileName: profileName, currentMode: modeName)
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

    private func isPressed(buttonID: ButtonID, gamepad: GCExtendedGamepad) -> Bool {
        switch buttonID {
        case .a:         return gamepad.buttonA.isPressed
        case .b:         return gamepad.buttonB.isPressed
        case .x:         return gamepad.buttonX.isPressed
        case .y:         return gamepad.buttonY.isPressed
        case .lb:        return gamepad.leftShoulder.isPressed
        case .rb:        return gamepad.rightShoulder.isPressed
        case .dpadUp:    return gamepad.dpad.up.isPressed
        case .dpadDown:  return gamepad.dpad.down.isPressed
        case .dpadLeft:  return gamepad.dpad.left.isPressed
        case .dpadRight: return gamepad.dpad.right.isPressed
        case .l3:        return gamepad.leftThumbstickButton?.isPressed == true
        case .r3:        return gamepad.rightThumbstickButton?.isPressed == true
        case .menu:      return gamepad.buttonMenu.isPressed
        case .options:   return gamepad.buttonOptions?.isPressed == true
        default:         return true
        }
    }
}
