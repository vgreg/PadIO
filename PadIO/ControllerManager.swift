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
    private let modePicker          = ModePickerController()
    private let debugOverlay        = DebugInputController()
    private let helpOverlay         = HelpController()
    private let modeNotification    = ModeNotificationController()

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

    /// Minimum axis deflection required to produce mouse/scroll events (eliminates stick drift).
    private static let axisDeadzone: Float = 0.1

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

            // Edge-triggered button dispatch
            for buttonID in ButtonID.allCases {
                let pressed = isPressed(buttonID: buttonID, gamepad: gamepad, threshold: threshold)
                let wasPressed = prev[buttonID] ?? false
                if pressed && !wasPressed {
                    handleMappedButton(buttonID)
                }
                prev[buttonID] = pressed
            }
            previousButtonStates[id] = prev

            // Continuous axis dispatch (mouse move / scroll) — only when no overlay is visible
            guard !helpOverlay.isVisible && !modePicker.isVisible else { continue }
            pollAxes(gamepad: gamepad, heldButtons: prev)
        }
    }

    /// Read and dispatch any active axis-to-pointer mappings for this tick.
    private func pollAxes(gamepad: GCExtendedGamepad, heldButtons: [ButtonID: Bool]) {
        let config = configLoader.config
        let bundleID = appObserver.frontmostBundleID
        guard let (profileName, profile) = mappingResolver.resolveProfile(bundleID: bundleID, config: config) else { return }
        let modeName = profileModes[profileName] ?? profile.defaultMode

        for axisID in AxisID.allCases {
            guard let mapping = mappingResolver.resolveAxisMapping(
                axisID: axisID,
                profile: profile,
                activeMode: modeName,
                config: config
            ) else { continue }

            let (rawX, rawY) = readAxisValues(axisID: axisID, gamepad: gamepad)

            // Apply deadzone — treat small deflections as zero to suppress stick drift
            let x = abs(rawX) > Self.axisDeadzone ? rawX : 0
            let y = abs(rawY) > Self.axisDeadzone ? rawY : 0
            guard x != 0 || y != 0 else { continue }

            // Apply modifier multiplier when the modifier button is held
            let modMult: CGFloat
            if let modBtn = mapping.modifierButton, heldButtons[modBtn] == true {
                modMult = mapping.modifierMultiplier
            } else {
                modMult = 1.0
            }

            // Compute per-tick pixel delta: axis * speed * modMult * inversionSign
            let xSign: CGFloat = mapping.xInverted ? -1 : 1
            let ySign: CGFloat = mapping.yInverted ? -1 : 1
            let dx = CGFloat(x) * mapping.xSpeed * modMult * xSign
            let dy = CGFloat(y) * mapping.ySpeed * modMult * ySign

            switch mapping.kind {
            case .mouseMove:
                // Screen Y axis is flipped: positive stick-Y = up = negative screen-Y
                inputHandler.emitMouseMove(dx: dx, dy: -dy)
                print("[PadIO] \(axisID.rawValue) | mouse_move dx=\(String(format: "%.1f", dx)) dy=\(String(format: "%.1f", -dy))")
            case .scroll:
                inputHandler.emitScroll(dx: dx, dy: dy)
                print("[PadIO] \(axisID.rawValue) | scroll dx=\(String(format: "%.1f", dx)) dy=\(String(format: "%.1f", dy))")
            }
        }
    }

    /// Returns the normalised (x, y) axis values for the given axis source (-1…+1).
    /// Dpad is treated as digital: produces ±1 per direction, 0 when not pressed.
    private func readAxisValues(axisID: AxisID, gamepad: GCExtendedGamepad) -> (x: Float, y: Float) {
        switch axisID {
        case .leftStick:
            return (gamepad.leftThumbstick.xAxis.value, gamepad.leftThumbstick.yAxis.value)
        case .rightStick:
            return (gamepad.rightThumbstick.xAxis.value, gamepad.rightThumbstick.yAxis.value)
        case .dpad:
            let x: Float = gamepad.dpad.right.isPressed ? 1 : (gamepad.dpad.left.isPressed ? -1 : 0)
            let y: Float = gamepad.dpad.up.isPressed    ? 1 : (gamepad.dpad.down.isPressed ? -1 : 0)
            return (x, y)
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
                debugOverlay.show(button: buttonID.rawValue, actionDescription: "no profile", postEventAccess: CGPreflightPostEventAccess())
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
                debugOverlay.show(button: buttonID.rawValue, actionDescription: "no mapping", postEventAccess: CGPreflightPostEventAccess())
            }
            return
        }

        if config.debugOverlay ?? false {
            debugOverlay.show(button: buttonID.rawValue, actionDescription: MappingResolver.describe(action), postEventAccess: CGPreflightPostEventAccess())
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

        helpOverlay.show(profileName: profileName, modeName: modeName, entries: entries) { [weak self] buttonName in
            guard let self else { return }
            // Re-resolve the action for the selected button and execute it
            guard let profileResult = self.mappingResolver.resolveProfile(
                bundleID: self.appObserver.frontmostBundleID,
                config: self.configLoader.config
            ) else { return }
            let activeMode = self.profileModes[profileResult.name] ?? profileResult.profile.defaultMode
            guard let buttonID = ButtonID(rawValue: buttonName) else { return }
            guard let action = self.mappingResolver.resolve(
                button: buttonID,
                profile: profileResult.profile,
                activeMode: activeMode,
                config: self.configLoader.config
            ) else { return }
            self.executeAction(action, profile: profileResult.profile, profileName: profileResult.name, currentMode: activeMode)
        }
    }

    private func executeAction(
        _ action: Action,
        profile: ProfileConfig,
        profileName: String,
        currentMode: String
    ) {
        switch action {
        case .keystroke(let keyCode, let flags):
            inputHandler.emitKeystroke(keyCode: keyCode, flags: flags)

        case .sequence(let steps, let delay):
            inputHandler.emitSequence(steps: steps, delay: delay)

        case .textInput(let text):
            inputHandler.emitText(text)

        case .mediaKey(let keyType):
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

        case .prevMode:
            let modes = profile.modes.keys.sorted()
            guard !modes.isEmpty else { return }
            let idx = modes.firstIndex(of: currentMode) ?? 0
            let newMode = modes[(idx - 1 + modes.count) % modes.count]
            switchMode(newMode, profileName: profileName)

        case .nextMode:
            let modes = profile.modes.keys.sorted()
            guard !modes.isEmpty else { return }
            let idx = modes.firstIndex(of: currentMode) ?? 0
            let newMode = modes[(idx + 1) % modes.count]
            switchMode(newMode, profileName: profileName)

        case .setMode(let name):
            guard profile.modes[name] != nil else {
                print("[PadIO] setMode: unknown mode '\(name)' in profile '\(profileName)'")
                return
            }
            switchMode(name, profileName: profileName)

        case .leftClick:
            inputHandler.emitMouseClick(button: .left)

        case .rightClick:
            inputHandler.emitMouseClick(button: .right)
        }
    }

    private func switchMode(_ modeName: String, profileName: String) {
        profileModes[profileName] = modeName
        activeModeName = modeName
        modeNotification.show(modeName: modeName)
        print("[PadIO] Mode changed to '\(modeName)' in profile '\(profileName)'")
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
