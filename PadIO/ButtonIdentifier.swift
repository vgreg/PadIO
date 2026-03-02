//
//  ButtonIdentifier.swift
//  PadIO
//
//  Created by Vincent Grégoire on 2026-03-02.
//
//  Maps GCControllerElement identities to canonical ButtonID values.

import GameController

/// Canonical button identifiers used as keys in the mapping config.
enum ButtonID: String, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
    case x = "X"
    case y = "Y"
    case lb = "LB"
    case rb = "RB"
    case lt = "LT"
    case rt = "RT"
    case dpadUp    = "dpad_up"
    case dpadDown  = "dpad_down"
    case dpadLeft  = "dpad_left"
    case dpadRight = "dpad_right"
    case l3        = "L3"
    case r3        = "R3"
    case menu      = "menu"
    case options   = "options"
    // Xbox extras
    case share   = "share"
    case paddle1 = "paddle1"
    case paddle2 = "paddle2"
    case paddle3 = "paddle3"
    case paddle4 = "paddle4"
}

/// Maps GCControllerElement references to ButtonID values.
struct ButtonIdentifier {

    /// Identify a standard extended gamepad element.
    /// Returns nil for analog-only axes (thumbstick X/Y) and the d-pad parent element
    /// (since individual direction elements fire alongside it).
    static func identify(
        element: GCControllerElement,
        gamepad: GCExtendedGamepad
    ) -> ButtonID? {
        // Face buttons
        if element === gamepad.buttonA { return .a }
        if element === gamepad.buttonB { return .b }
        if element === gamepad.buttonX { return .x }
        if element === gamepad.buttonY { return .y }

        // Bumpers
        if element === gamepad.leftShoulder  { return .lb }
        if element === gamepad.rightShoulder { return .rb }

        // Triggers (analog, threshold applied in ControllerManager)
        if element === gamepad.leftTrigger  { return .lt }
        if element === gamepad.rightTrigger { return .rt }

        // D-Pad individual directions (parent fires alongside; skip parent to avoid double-fire)
        if element === gamepad.dpad.up    { return .dpadUp }
        if element === gamepad.dpad.down  { return .dpadDown }
        if element === gamepad.dpad.left  { return .dpadLeft }
        if element === gamepad.dpad.right { return .dpadRight }
        if element === gamepad.dpad       { return nil }

        // Thumbstick clicks
        if element === gamepad.leftThumbstickButton  { return .l3 }
        if element === gamepad.rightThumbstickButton { return .r3 }

        // Menu buttons
        if element === gamepad.buttonMenu    { return .menu }
        if element === gamepad.buttonOptions { return .options }

        // Thumbstick axes — not discrete buttons, skip
        if element === gamepad.leftThumbstick ||
           element === gamepad.leftThumbstick.xAxis ||
           element === gamepad.leftThumbstick.yAxis ||
           element === gamepad.rightThumbstick ||
           element === gamepad.rightThumbstick.xAxis ||
           element === gamepad.rightThumbstick.yAxis {
            return nil
        }

        // Home button is typically reserved by the system
        if element === gamepad.buttonHome { return nil }

        return nil
    }

    /// Identify Xbox-specific extended buttons (share, paddles).
    static func identifyXbox(
        element: GCControllerElement,
        xbox: GCXboxGamepad
    ) -> ButtonID? {
        if let btn = xbox.buttonShare,   element === btn { return .share }
        if let btn = xbox.paddleButton1, element === btn { return .paddle1 }
        if let btn = xbox.paddleButton2, element === btn { return .paddle2 }
        if let btn = xbox.paddleButton3, element === btn { return .paddle3 }
        if let btn = xbox.paddleButton4, element === btn { return .paddle4 }
        return nil
    }
}
