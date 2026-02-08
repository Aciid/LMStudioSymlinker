// LMStudioSymlinkerApp.swift

import SwiftUI
import AppKit
import Tray
import NoLaunchWin
import LMStudioSymlinkerCore

extension Notification.Name {
    static let settingsWindowShouldBecomeKey = Notification.Name("settingsWindowShouldBecomeKey")
}

@main
struct LMStudioSymlinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            NoLaunchWinView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tray: Tray!
    let settingsViewModel: SettingsViewModel
    private var settingsWindow: NSWindow?
    private let symlinkService: SymlinkService

    override init() {
        let driveProvider = DiskService.shared
        self.symlinkService = SymlinkService(driveProvider: driveProvider)
        self.settingsViewModel = SettingsViewModel(
            config: ConfigurationService.shared,
            driveProvider: driveProvider,
            symlinkService: symlinkService,
            systemService: LaunchAgentService.shared
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupTray()
        setupSettingsWindowNotifications()
        startVolumeMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        VolumeMonitorService.shared.stopMonitoring()
    }

    // MARK: - Tray Setup

    private func setupTray() {
        tray = Tray.install(systemSymbolName: "link") { [weak self] tray in
            self?.configureTrayMenu(tray)
        }
    }

    private func configureTrayMenu(_ tray: Tray) {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        tray.setMenu(menu: menu)
        tray.statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openSettings() {
        Task { await settingsViewModel.refreshStatus() }
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        createSettingsWindow()
    }

    private func setupSettingsWindowNotifications() {
        NotificationCenter.default.addObserver(
            forName: .settingsWindowShouldBecomeKey,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settingsWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func createSettingsWindow() {
        let settingsView = SettingsView(viewModel: settingsViewModel)

        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = settingsViewModel.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 700))
        window.minSize = NSSize(width: 500, height: 650)
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Volume Monitoring

    private func startVolumeMonitoring() {
        let monitor = VolumeMonitorService.shared

        monitor.onVolumeMount = { [weak self] path in
            Task { @MainActor [weak self] in
                await self?.handleVolumeMount(path: path)
            }
        }

        monitor.onVolumeUnmount = { [weak self] path in
            Task { @MainActor [weak self] in
                await self?.handleVolumeUnmount(path: path)
            }
        }

        monitor.startMonitoring()
    }

    private func handleVolumeMount(path: String) async {
        guard let selectedDrive = settingsViewModel.selectedDrive,
              path == selectedDrive.path else {
            return
        }

        let modelsPath = PathHelper.modelsSymlinkPath
        let hubPath = PathHelper.hubSymlinkPath

        do {
            try await symlinkService.handleVolumeMount(
                volumeUUID: selectedDrive.uuid,
                modelsSymlinkPath: modelsPath,
                hubSymlinkPath: hubPath
            )
        } catch {
            print("Failed to handle volume mount: \(error)")
        }
    }

    private func handleVolumeUnmount(path: String) async {
        guard let selectedDrive = settingsViewModel.selectedDrive,
              path == selectedDrive.path else {
            return
        }

        let modelsPath = PathHelper.modelsSymlinkPath
        let hubPath = PathHelper.hubSymlinkPath

        await symlinkService.handleVolumeUnmount(
            modelsSymlinkPath: modelsPath,
            hubSymlinkPath: hubPath
        )
    }
}
