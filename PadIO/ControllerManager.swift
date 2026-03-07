//
//  ControllerManager.swift
//  PadIO
//
//  Orchestrates controller discovery, profile/mode resolution, and action execution.

import Foundation
import Combine
import GameController
import CoreGraphics
import QuartzCore

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
    private let customMenu          = CustomMenuController()
    private let hapticController    = HapticController()
    private lazy var hapticObserver = HapticEventObserver(hapticController: hapticController)

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

        // Re-resolve profile and reconfigure haptics when config reloads
        configLoader.$config
            .sink { [weak self] config in
                self?.refreshActiveProfile()
                self?.hapticObserver.configure(
                    config: config,
                    frontmostBundleID: self?.appObserver.frontmostBundleID
                )
            }
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
        let id = ObjectIdentifier(controller)
        connectedControllers.removeAll { $0 == controller }
        previousButtonStates.removeValue(forKey: id)
        holdStates.removeValue(forKey: id)
        hapticController.controllerDisconnected(controller)
        print("[PadIO] Controller disconnected: \(controller.vendorName ?? "Unknown")")
    }

    // MARK: - Polling

    // Previous pressed state per controller, keyed by ObjectIdentifier
    private var previousButtonStates: [ObjectIdentifier: [ButtonID: Bool]] = [:]

    /// Minimum axis deflection required to produce mouse/scroll events (eliminates stick drift).
    private static let axisDeadzone: Float = 0.1

    // MARK: - Hold state machine

    /// Duration in seconds a button must be held before the hold action fires.
    private static let holdThreshold: CFTimeInterval = 0.3

    /// Context captured at the moment a hold-capable button is first pressed.
    private struct HoldContext {
        let pressAction: Action
        let holdAction: Action
        let profile: ProfileConfig
        let profileName: String
        let currentMode: String
    }

    /// Per-button hold tracking state.
    private enum HoldState {
        case pending(pressTime: CFTimeInterval, context: HoldContext)
        case held(context: HoldContext)
    }

    /// Active hold states per controller and button.
    private var holdStates: [ObjectIdentifier: [ButtonID: HoldState]] = [:]

    private func startPollingTimer() {
        // Poll at ~60Hz — fast enough to catch quick taps
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollControllers() }
        }
    }

    private func pollControllers() {
        let threshold = Float(configLoader.config.triggerThreshold ?? 0.5)
        let now = CACurrentMediaTime()
        for controller in GCController.controllers() {
            guard let gamepad = controller.extendedGamepad else { continue }
            let id = ObjectIdentifier(controller)
            var prev = previousButtonStates[id] ?? [:]
            var holds = holdStates[id] ?? [:]

            for buttonID in ButtonID.allCases {
                let pressed = isPressed(buttonID: buttonID, gamepad: gamepad, threshold: threshold)
                let wasPressed = prev[buttonID] ?? false

                if pressed && !wasPressed {
                    // Press edge — check if this binding has a hold action
                    if let holdConfig = resolveHoldConfig(buttonID: buttonID, heldButtons: prev) {
                        holds[buttonID] = .pending(pressTime: now, context: holdConfig)
                    } else {
                        handleMappedButton(buttonID, heldButtons: prev)
                    }
                } else if pressed && wasPressed {
                    // Still held — check for threshold crossing
                    if case .pending(let pressTime, let context) = holds[buttonID],
                       now - pressTime >= Self.holdThreshold {
                        // Threshold exceeded — fire hold action
                        let holdAction = convertToHoldAction(context.holdAction)
                        executeAction(holdAction, profile: context.profile, profileName: context.profileName, currentMode: context.currentMode)
                        holds[buttonID] = .held(context: context)
                    }
                } else if !pressed && wasPressed {
                    // Release edge — handle hold state
                    if let holdState = holds[buttonID] {
                        switch holdState {
                        case .pending(_, let context):
                            // Released before threshold — fire the tap (press) action
                            executeAction(context.pressAction, profile: context.profile, profileName: context.profileName, currentMode: context.currentMode)
                        case .held(let context):
                            // Released after hold — fire the release counterpart
                            let releaseAction = releaseAction(for: context.holdAction)
                            executeAction(releaseAction, profile: context.profile, profileName: context.profileName, currentMode: context.currentMode)
                        }
                        holds.removeValue(forKey: buttonID)
                    }
                }
                prev[buttonID] = pressed
            }
            previousButtonStates[id] = prev
            holdStates[id] = holds

            // Continuous axis dispatch (mouse move / scroll) — only when no overlay is visible
            guard !helpOverlay.isVisible && !modePicker.isVisible && !customMenu.isVisible else { continue }
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
            let deadX = abs(rawX) > Self.axisDeadzone ? rawX : Float(0)
            let deadY = abs(rawY) > Self.axisDeadzone ? rawY : Float(0)
            guard deadX != 0 || deadY != 0 else { continue }

            // Apply quadratic response curve: preserves sign, amplifies large inputs,
            // gives fine control near center while keeping full-deflection speed.
            let x = deadX * abs(deadX)
            let y = deadY * abs(deadY)

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
                if let btn = heldMouseButton() {
                    inputHandler.emitMouseDrag(dx: dx, dy: -dy, button: btn)
                } else {
                    inputHandler.emitMouseMove(dx: dx, dy: -dy)
                }
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

    private func handleMappedButton(_ buttonID: ButtonID, heldButtons: [ButtonID: Bool] = [:]) {
        // Let the help overlay consume all input while visible
        if helpOverlay.handleButton(buttonID) {
            return
        }

        // Let the mode picker consume the input first when it is visible
        if modePicker.handleButton(buttonID) {
            return
        }

        // Let a custom menu consume input when it is visible
        if customMenu.handleButton(buttonID) {
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
            heldButtons: heldButtons,
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
            // Merge any active modifier holds so held modifiers aren't dropped
            let mergedFlags = flags.union(heldModifierFlags())
            inputHandler.emitKeystroke(keyCode: keyCode, flags: mergedFlags)

        case .sequence(let steps, let delay):
            // Merge any active modifier holds into each step
            let modFlags = heldModifierFlags()
            let mergedSteps = steps.map { (keyCode: $0.keyCode, flags: $0.flags.union(modFlags)) }
            // Dispatch off main thread — usleep in emitSequence blocks the calling thread,
            // which prevents CGEvents from being delivered when triggered from menu callbacks.
            let handler = inputHandler
            DispatchQueue.global(qos: .userInteractive).async {
                handler.emitSequence(steps: mergedSteps, delay: delay)
            }

        case .textInput(let text):
            inputHandler.emitText(text)

        case .mediaKey(let keyType):
            inputHandler.emitMediaKey(keyType: keyType)

        case .modeSelect:
            let config = configLoader.config
            let modes = allModeNames(profile: profile, config: config)
            guard !modes.isEmpty else { return }
            modePicker.show(modes: modes, currentMode: currentMode) { [weak self] selectedMode in
                guard let self else { return }
                self.profileModes[profileName] = selectedMode
                self.activeModeName = selectedMode
                print("[PadIO] Mode changed to '\(selectedMode)' in profile '\(profileName)'")
            }

        case .prevMode:
            let modes = allModeNames(profile: profile, config: configLoader.config)
            guard !modes.isEmpty else { return }
            let idx = modes.firstIndex(of: currentMode) ?? 0
            let newMode = modes[(idx - 1 + modes.count) % modes.count]
            switchMode(newMode, profileName: profileName)

        case .nextMode:
            let modes = allModeNames(profile: profile, config: configLoader.config)
            guard !modes.isEmpty else { return }
            let idx = modes.firstIndex(of: currentMode) ?? 0
            let newMode = modes[(idx + 1) % modes.count]
            switchMode(newMode, profileName: profileName)

        case .setMode(let name):
            let config = configLoader.config
            guard profile.modes[name] != nil || config.sharedModes?[name] != nil else {
                print("[PadIO] setMode: unknown mode '\(name)' in profile '\(profileName)'")
                return
            }
            switchMode(name, profileName: profileName)

        case .openMenu(let name):
            let config = configLoader.config
            guard let menuConfig = config.menus[name] else {
                print("[PadIO] openMenu: unknown menu '\(name)'")
                return
            }
            let labels = menuConfig.items.map { $0.label }
            customMenu.show(title: name, labels: labels) { [weak self] index in
                guard let self else { return }
                guard menuConfig.items.indices.contains(index) else { return }
                let itemAction = menuConfig.items[index].action
                guard let action = MappingResolver().buildActionPublic(from: itemAction, mappingConfig: self.configLoader.config) else { return }
                self.executeAction(action, profile: profile, profileName: profileName, currentMode: currentMode)
            }

        case .leftClick:
            inputHandler.emitMouseClick(button: .left)

        case .rightClick:
            inputHandler.emitMouseClick(button: .right)

        case .keyboardViewer:
            inputHandler.toggleKeyboardViewer()

        case .nextInputSource:
            inputHandler.cycleToNextInputSource()

        case .rumble(let intensity, let sharpness, let duration):
            let params = RumbleParams(
                intensity: Float(intensity),
                sharpness: Float(sharpness),
                duration: duration
            )
            hapticController.rumbleAll(params: params)

        case .leftClickHold:
            inputHandler.emitMouseDown(button: .left)

        case .leftClickRelease:
            inputHandler.emitMouseUp(button: .left)

        case .rightClickHold:
            inputHandler.emitMouseDown(button: .right)

        case .rightClickRelease:
            inputHandler.emitMouseUp(button: .right)

        case .keyDown(let keyCode, let flags):
            inputHandler.emitKeyDown(keyCode: keyCode, flags: flags.union(heldModifierFlags()))

        case .keyUp(let keyCode, let flags):
            inputHandler.emitKeyUp(keyCode: keyCode, flags: flags.union(heldModifierFlags()))

        case .modifierHold(let flags):
            inputHandler.emitModifierDown(flags: flags)

        case .modifierRelease(let flags):
            inputHandler.emitModifierUp(flags: flags)
        }
    }

    // MARK: - Hold helpers

    /// Checks if the binding for a button has a `hold` field. If so, builds both
    /// the press and hold actions and returns them as a HoldContext.
    private func resolveHoldConfig(buttonID: ButtonID, heldButtons: [ButtonID: Bool]) -> HoldContext? {
        let config = configLoader.config
        let bundleID = appObserver.frontmostBundleID
        guard let (profileName, profile) = mappingResolver.resolveProfile(bundleID: bundleID, config: config) else { return nil }
        let modeName = profileModes[profileName] ?? profile.defaultMode

        guard let actionConfig = mappingResolver.resolveActionConfig(
            button: buttonID,
            heldButtons: heldButtons,
            profile: profile,
            activeMode: modeName,
            config: config
        ) else { return nil }

        // Only enter hold mode if the config has a hold field
        guard let holdActionConfig = actionConfig.hold else { return nil }

        guard let pressAction = mappingResolver.resolve(
            button: buttonID,
            heldButtons: heldButtons,
            profile: profile,
            activeMode: modeName,
            config: config
        ) else { return nil }

        guard let holdAction = MappingResolver().buildActionPublic(from: holdActionConfig, mappingConfig: config) else { return nil }

        return HoldContext(
            pressAction: pressAction,
            holdAction: holdAction,
            profile: profile,
            profileName: profileName,
            currentMode: modeName
        )
    }

    /// Converts a hold action to its "activated" form. Keystrokes become key-down only.
    private func convertToHoldAction(_ action: Action) -> Action {
        switch action {
        case .keystroke(let keyCode, let flags):
            return .keyDown(keyCode: keyCode, flags: flags)
        default:
            return action
        }
    }

    /// Returns the release counterpart for a hold action.
    private func releaseAction(for holdAction: Action) -> Action {
        switch holdAction {
        case .leftClickHold:
            return .leftClickRelease
        case .rightClickHold:
            return .rightClickRelease
        case .keystroke(let keyCode, let flags):
            return .keyUp(keyCode: keyCode, flags: flags)
        case .modifierHold(let flags):
            return .modifierRelease(flags: flags)
        default:
            // For actions without an explicit release, use a no-op by returning the same
            // (executeAction will just fire the action again, which is fine for one-shots)
            return .keyUp(keyCode: 0, flags: [])
        }
    }

    /// Returns the union of all modifier flags currently held via modifierHold actions.
    private func heldModifierFlags() -> CGEventFlags {
        var flags: CGEventFlags = []
        for (_, buttons) in holdStates {
            for (_, state) in buttons {
                if case .held(let context) = state,
                   case .modifierHold(let heldFlags) = context.holdAction {
                    flags.insert(heldFlags)
                }
            }
        }
        return flags
    }

    /// Returns true if any button on any controller has an active mouse hold.
    private func isMouseHeld() -> Bool {
        for (_, buttons) in holdStates {
            for (_, state) in buttons {
                if case .held(let context) = state {
                    switch context.holdAction {
                    case .leftClickHold, .rightClickHold:
                        return true
                    default:
                        continue
                    }
                }
            }
        }
        return false
    }

    /// Returns the mouse button being held, if any.
    private func heldMouseButton() -> CGMouseButton? {
        for (_, buttons) in holdStates {
            for (_, state) in buttons {
                if case .held(let context) = state {
                    switch context.holdAction {
                    case .leftClickHold:
                        return .left
                    case .rightClickHold:
                        return .right
                    default:
                        continue
                    }
                }
            }
        }
        return nil
    }

    /// Returns the sorted union of profile mode names and shared mode names.
    private func allModeNames(profile: ProfileConfig, config: MappingConfig) -> [String] {
        var names = Set(profile.modes.keys)
        if let shared = config.sharedModes { names.formUnion(shared.keys) }
        return names.sorted()
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
