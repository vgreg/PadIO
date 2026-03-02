//
//  PadIOApp.swift
//  PadIO
//
//  Created by Vincent Grégoire on 2026-03-02.
//

import SwiftUI

@main
struct PadIOApp: App {
    @StateObject private var controllerManager = ControllerManager()

    init() {
        InputHandler.requestAccessibilityPermission()
    }

    var body: some Scene {
        MenuBarExtra("PadIO", systemImage: "gamecontroller") {
            MenuBarView()
                .environmentObject(controllerManager)
                .environmentObject(controllerManager.appObserver)
                .environmentObject(controllerManager.configLoader)
        }
        .menuBarExtraStyle(.menu)
    }
}
