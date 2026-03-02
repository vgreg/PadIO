//
//  ContentView.swift
//  PadIO
//
//  Created by Vincent Grégoire on 2026-03-02.
//

import SwiftUI
import GameController
import AppKit

/// The pull-down menu shown when the user clicks the PadIO menu bar icon.
struct MenuBarView: View {
    @EnvironmentObject var controllerManager: ControllerManager
    @EnvironmentObject var appObserver: AppObserver
    @EnvironmentObject var configLoader: ConfigLoader
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Accessibility permission warning
        if !InputHandler.hasAccessibilityPermission() {
            Button("Grant Accessibility Access…") {
                InputHandler.requestAccessibilityPermission()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    openURL(url)
                }
            }
            Divider()
        }

        // Current profile / mode
        profileSection

        Divider()

        // Config status
        configSection

        Divider()

        // Connected controllers
        if controllerManager.connectedControllers.isEmpty {
            Text("No controller connected")
                .foregroundStyle(.secondary)
        } else {
            ForEach(controllerManager.connectedControllers, id: \.self) { controller in
                Label(
                    controller.vendorName ?? "Controller",
                    systemImage: "gamecontroller.fill"
                )
            }
        }

        Divider()

        Button("Quit PadIO") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Profile / Mode section

    @ViewBuilder
    private var profileSection: some View {
        if let bundleID = appObserver.frontmostBundleID {
            Label(appDisplayName(bundleID), systemImage: "app.fill")
        } else {
            Text("No app focused")
                .foregroundStyle(.secondary)
        }

        if let profileName = controllerManager.activeProfileName {
            if let modeName = controllerManager.activeModeName {
                Label("\(profileName) · \(modeName)", systemImage: "slider.horizontal.3")
            } else {
                Label(profileName, systemImage: "slider.horizontal.3")
            }
        } else {
            Text("No profile matched")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Config section

    @ViewBuilder
    private var configSection: some View {
        if let error = configLoader.configError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(error)
        } else {
            let count = configLoader.config.profiles.count
            Label("\(count) profile\(count == 1 ? "" : "s") loaded", systemImage: "doc.text.fill")
        }

        Button("Reload Config") {
            configLoader.loadConfig()
        }
    }

    // MARK: - Helpers

    private func appDisplayName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
