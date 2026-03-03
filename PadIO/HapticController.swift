//
//  HapticController.swift
//  PadIO
//
//  Manages force-feedback (rumble) for connected game controllers.
//  Uses the GCDeviceHaptics → CHHapticEngine bridge introduced in macOS 11.
//
//  Two trigger sources are supported:
//    1. Action-triggered: the "rumble" action type fires a one-shot rumble.
//    2. System events: optional rumble on system beep / notification delivery.

import Foundation
import GameController
import CoreHaptics

// MARK: - Rumble parameters

struct RumbleParams {
    var intensity: Float    // 0.0–1.0
    var sharpness: Float    // 0.0–1.0
    var duration: TimeInterval
}

// MARK: - HapticController

/// Drives haptic feedback on all connected GCControllers.
/// Each controller gets its own CHHapticEngine per locality (created lazily).
@MainActor
final class HapticController {

    // Cache of engines keyed by (controller ObjectIdentifier, locality)
    private var engines: [EngineKey: CHHapticEngine] = [:]

    // MARK: - Public API

    /// Fire a one-shot rumble on every connected controller that supports haptics.
    func rumbleAll(params: RumbleParams) {
        for controller in GCController.controllers() {
            rumble(controller: controller, params: params)
        }
    }

    /// Fire a one-shot rumble on a specific controller.
    func rumble(controller: GCController, params: RumbleParams) {
        guard let haptics = controller.haptics else { return }
        let locality: GCHapticsLocality = .default
        guard haptics.supportedLocalities.contains(locality) else { return }

        let engine = cachedEngine(for: controller, locality: locality, haptics: haptics)
        playRumble(engine: engine, params: params)
    }

    /// Remove cached engines for a disconnected controller.
    func controllerDisconnected(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        engines = engines.filter { $0.key.controllerID != id }
    }

    // MARK: - Engine cache

    private struct EngineKey: Hashable {
        let controllerID: ObjectIdentifier
        let locality: GCHapticsLocality
    }

    private func cachedEngine(
        for controller: GCController,
        locality: GCHapticsLocality,
        haptics: GCDeviceHaptics
    ) -> CHHapticEngine? {
        let key = EngineKey(controllerID: ObjectIdentifier(controller), locality: locality)
        if let existing = engines[key] { return existing }
        guard let engine = haptics.createEngine(withLocality: locality) else { return nil }

        // Start the engine; it may need to be restarted if it stops
        do {
            try engine.start()
        } catch {
            print("[PadIO] Haptic engine start failed: \(error)")
            return nil
        }

        // Re-start automatically if the engine stops (e.g., controller sleep)
        engine.stoppedHandler = { [weak self] reason in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try engine.start()
                } catch {
                    print("[PadIO] Haptic engine restart failed: \(error)")
                    self.engines.removeValue(forKey: key)
                }
            }
        }

        engines[key] = engine
        return engine
    }

    // MARK: - Playback

    private func playRumble(engine: CHHapticEngine?, params: RumbleParams) {
        guard let engine else { return }
        do {
            let intensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: max(0, min(1, params.intensity))
            )
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: max(0, min(1, params.sharpness))
            )
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: params.duration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[PadIO] Haptic playback failed: \(error)")
        }
    }
}

// MARK: - System event observer

/// Watches for system alert sounds and notification deliveries,
/// firing controller rumble when enabled in config.
@MainActor
final class HapticEventObserver {
    private weak var hapticController: HapticController?
    private var observers: [NSObjectProtocol] = []

    init(hapticController: HapticController) {
        self.hapticController = hapticController
    }

    deinit {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }

    // MARK: - Setup

    func configure(config: MappingConfig, frontmostBundleID: String?) {
        // Remove previous observers
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers = []

        guard let hapticConfig = config.haptics else { return }

        if let beepParams = hapticConfig.onSystemBeep {
            listenForBeep(params: beepParams)
        }

        if let notifConfig = hapticConfig.onNotification {
            listenForNotification(config: notifConfig, frontmostBundleID: frontmostBundleID)
        }
    }

    // MARK: - Beep observer

    private func listenForBeep(params: HapticsConfig.RumbleEventConfig) {
        // macOS posts this distributed notification whenever a system alert sound plays
        let obs = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.sound.alert.played"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                let p = RumbleParams(
                    intensity: Float(params.intensity ?? 0.5),
                    sharpness: Float(params.sharpness ?? 0.3),
                    duration: params.duration ?? 0.2
                )
                self?.hapticController?.rumbleAll(params: p)
                print("[PadIO] Haptic: system beep rumble")
            }
        }
        observers.append(obs)
    }

    // MARK: - Notification observer

    private func listenForNotification(config: HapticsConfig.NotificationRumbleConfig, frontmostBundleID: String?) {
        // macOS posts this distributed notification when any app delivers a user notification
        let obs = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.usernotifications.notification-posted"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }

                // If app filter is set, only rumble when the sending bundle ID matches
                if let allowedApps = config.apps, !allowedApps.isEmpty {
                    // The notification object or userInfo may carry the sender bundle ID
                    let senderID = notification.object as? String
                        ?? notification.userInfo?["bundleID"] as? String
                    guard let senderID, allowedApps.contains(senderID) else { return }
                }

                let p = RumbleParams(
                    intensity: Float(config.intensity ?? 0.6),
                    sharpness: Float(config.sharpness ?? 0.4),
                    duration: config.duration ?? 0.25
                )
                self.hapticController?.rumbleAll(params: p)
                print("[PadIO] Haptic: notification rumble")
            }
        }
        observers.append(obs)
    }
}
