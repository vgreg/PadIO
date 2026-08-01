//
//  ContextObserver.swift
//  PadIO
//
//  Watches ~/.config/padio/context — a single-token text file written by an
//  external producer (e.g. the herdr bridge) to tell PadIO which app is in the
//  focused pane. Publishes the trimmed token; mapping it to a mode lives in
//  ControllerManager. Models the same DispatchSource pattern as AppObserver /
//  ConfigLoader, but re-arms on rename/delete so atomic replaces keep firing.

import Foundation
import Combine

@MainActor
final class ContextObserver: ObservableObject {
    /// Current context token, or nil when the file is missing or empty.
    @Published private(set) var context: String? = nil

    static let contextPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/padio/context"
    }()

    private static let directoryPath: String = (contextPath as NSString).deletingLastPathComponent

    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var directoryMonitorSource: DispatchSourceFileSystemObject?

    init() {
        loadContext()
        // The directory monitor catches the file being created, deleted, or atomically
        // replaced (temp file + rename, the producer contract). The file monitor catches
        // in-place writes. Together they cover every way the token can change.
        setupDirectoryMonitor()
        setupFileMonitor()
    }

    deinit {
        fileMonitorSource?.cancel()
        directoryMonitorSource?.cancel()
    }

    // MARK: - Load

    private func loadContext() {
        let path = Self.contextPath
        // Missing or unreadable file means "no context" — not an error. The bridge may
        // not be running, and PadIO must behave exactly as it does with no file present.
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let raw = String(data: data, encoding: .utf8) else {
            updateContext(nil)
            return
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        updateContext(trimmed.isEmpty ? nil : trimmed)
    }

    /// Publishes a new token only when it actually changed (dedupe on the read side).
    private func updateContext(_ newValue: String?) {
        guard newValue != context else { return }
        context = newValue
        print("[PadIO] Context: \(newValue ?? "nil")")
    }

    // MARK: - Directory monitor

    /// Watches the parent directory so a context file created *after* launch is picked up,
    /// and so atomic replaces (rename into the directory) are observed.
    private func setupDirectoryMonitor() {
        let fd = open(Self.directoryPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.loadContext()
                // The file may have just appeared or been replaced — (re)establish its watch.
                self.setupFileMonitor()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        directoryMonitorSource = source
    }

    // MARK: - File monitor (re-armed on rename/delete)

    /// Watches the context file itself for in-place writes. The fd goes stale after an
    /// atomic replace or delete, so the handler cancels and re-establishes the source.
    private func setupFileMonitor() {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil

        // File may not exist yet; the directory monitor will re-arm this once it appears.
        let fd = open(Self.contextPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.loadContext()
                self.setupFileMonitor()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitorSource = source
    }
}
