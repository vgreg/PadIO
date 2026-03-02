//
//  AppObserver.swift
//  PadIO
//
//  Event-driven frontmost app watcher. Replaces the heavyweight ContextDetector.
//  Only tracks the bundle ID of the frontmost application; profile/mode resolution
//  happens in ControllerManager using the config.

import AppKit
import Combine

@MainActor
final class AppObserver: ObservableObject {
    /// Bundle ID of the currently frontmost application, or nil if unknown.
    @Published private(set) var frontmostBundleID: String? = nil

    private var observers: [NSObjectProtocol] = []

    init() {
        // Seed with current value immediately
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let nc = NSWorkspace.shared.notificationCenter
        let obs = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.frontmostBundleID = app?.bundleIdentifier
            }
        }
        observers.append(obs)
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
    }
}
