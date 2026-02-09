// SettingsViewModel.swift - Uses protocol types from Core (shared with Linux CLI)

import Foundation
import SwiftUI
import Combine
import LMStudioSymlinkerCore

@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - State

    var selectedDrive: DriveInfo?
    var availableDrives: [DriveInfo] = []
    var isLoadingDrives = false
    var initializationState: InitializationState = .uninitialized
    var symlinkStatus: SymlinkStatus?

    var targetDiskStorageUsage: String = ""
    var lmStudioModelsUsage: String = ""
    var isLMStudioModelsExist = false

    var progressMessage: String = ""
    var isInitializing = false
    var isInstallingService = false

    var showError = false
    var errorMessage = ""

    var isServiceInstalled = false
    var serviceStatus: [String: Bool] = [:]

    var startAtLogin = false

    // MARK: - Services (injected, protocol-based)

    private let config: ConfigStorage
    private let driveProvider: DriveProviding
    private let symlinkService: SymlinkService
    private let systemService: SystemServiceInstalling

    // MARK: - Computed Properties

    var windowTitle: String {
        switch initializationState {
        case .uninitialized:
            return "LM Studio Symlink Manager - Uninitialized"
        case .initialized:
            return "LM Studio Symlink Manager"
        case .error:
            return "LM Studio Symlink Manager - Error"
        }
    }

    var canInitialize: Bool {
        selectedDrive != nil && !isInitializing && initializationState != .initialized
    }

    var canInstallService: Bool {
        selectedDrive != nil && initializationState == .initialized && !isInstallingService
    }

    // MARK: - Initialization

    init(config: ConfigStorage, driveProvider: DriveProviding, symlinkService: SymlinkService, systemService: SystemServiceInstalling) {
        self.config = config
        self.driveProvider = driveProvider
        self.symlinkService = symlinkService
        self.systemService = systemService
        Task {
            await loadSavedConfiguration()
            await refreshDriveList()
            await updateStorageInfo()
            await checkSymlinkStatus()
            await checkServiceStatus()
            await loadLoginItemStatus()
        }
    }

    // MARK: - Configuration

    private func loadSavedConfiguration() async {
        let loaded = await config.loadConfiguration()

        if let path = loaded.externalDrivePath,
           let uuid = loaded.externalDriveUUID,
           let name = loaded.externalDriveName {
            if let driveInfo = await driveProvider.getDriveInfo(for: path),
               driveInfo.uuid == uuid {
                selectedDrive = driveInfo
            } else {
                selectedDrive = DriveInfo(
                    path: path,
                    name: name,
                    uuid: uuid,
                    isExternal: true,
                    isRemovable: true
                )
            }
        }

        if loaded.isInitialized {
            initializationState = .initialized
        }
    }

    private func saveConfiguration() async {
        let toSave = AppConfiguration(
            externalDrivePath: selectedDrive?.path,
            externalDriveUUID: selectedDrive?.uuid,
            externalDriveName: selectedDrive?.name,
            isInitialized: initializationState == .initialized
        )
        await config.saveConfiguration(toSave)
    }

    // MARK: - Drive Management

    func refreshDriveList() async {
        isLoadingDrives = true
        defer { isLoadingDrives = false }

        do {
            availableDrives = try await driveProvider.getExternalDrives()
        } catch {
            showError(message: "Failed to load drives: \(error.localizedDescription)")
        }
    }

    /// Re-check symlink status and storage so the UI reflects current filesystem state (e.g. after symlinks were removed elsewhere).
    func refreshStatus() async {
        await updateStorageInfo()
        await checkSymlinkStatus()
    }

    func selectDrive(_ drive: DriveInfo) async {
        selectedDrive = drive
        await saveConfiguration()
        await updateStorageInfo()
        await checkSymlinkStatus()
    }

    func openDrivePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.message = "Select an external drive for LM Studio models"

        panel.begin { [weak self] response in
            defer {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .settingsWindowShouldBecomeKey, object: nil)
                }
            }
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor [weak self] in
                await self?.handleSelectedVolume(url)
            }
        }
    }

    private func handleSelectedVolume(_ url: URL) async {
        let path = url.path

        // Validate it's under /Volumes
        guard path.hasPrefix("/Volumes/") else {
            showError(message: "Please select a volume under /Volumes")
            return
        }

        // Get drive info
        guard let driveInfo = await driveProvider.getDriveInfo(for: path) else {
            showError(message: "Could not get information for selected volume")
            return
        }

        // Validate it's external
        guard driveInfo.isExternal || driveInfo.isRemovable else {
            showError(message: "Please select an external or removable drive")
            return
        }

        await selectDrive(driveInfo)
    }

    // MARK: - Storage Info

    private func updateStorageInfo() async {
        guard let drive = selectedDrive else {
            targetDiskStorageUsage = ""
            return
        }

        if let storageInfo = await driveProvider.getVolumeStorageInfo(for: drive.path) {
            targetDiskStorageUsage = "\(storageInfo.usedSize) used / \(storageInfo.totalSize)"
        } else {
            targetDiskStorageUsage = "Unknown"
        }

        let modelsPath = driveProvider.modelsSymlinkPath
        isLMStudioModelsExist = await driveProvider.lmStudioModelsExist()

        if isLMStudioModelsExist {
            if let usage = await driveProvider.getStorageUsage(for: modelsPath) {
                lmStudioModelsUsage = usage
            }
        }
    }

    // MARK: - Symlink Status

    private func checkSymlinkStatus() async {
        symlinkStatus = await driveProvider.getSymlinkStatus()
        updateInitializationStateFromSymlinks()
    }

    /// Sync initialization state with actual symlink state: initialized when both point to selected drive, uninitialized when not.
    private func updateInitializationStateFromSymlinks() {
        guard let drive = selectedDrive, let status = symlinkStatus else { return }
        let prefix = drive.path.hasSuffix("/") ? drive.path : drive.path + "/"
        let modelsPointsToDrive: Bool = {
            if case .symlink(let target) = status.modelsPathType {
                return target == drive.path + "/models" || target.hasPrefix(prefix)
            }
            return false
        }()
        let hubPointsToDrive: Bool = {
            if case .symlink(let target) = status.hubPathType {
                return target == drive.path + "/hub" || target.hasPrefix(prefix)
            }
            return false
        }()
        if modelsPointsToDrive && hubPointsToDrive {
            if initializationState != .initialized {
                initializationState = .initialized
                Task { await saveConfiguration() }
            }
        } else if initializationState == .initialized {
            // Symlinks removed or point elsewhere – reflect current state
            initializationState = .uninitialized
            Task { await saveConfiguration() }
        }
    }

    // MARK: - Initialize

    func initialize() async {
        guard let drive = selectedDrive else {
            showError(message: "Please select a target drive first")
            return
        }

        isInitializing = true
        progressMessage = "Starting initialization..."

        do {
            let modelsPath = driveProvider.modelsSymlinkPath
            let hubPath = driveProvider.hubSymlinkPath

            try await symlinkService.initialize(
                volumePath: drive.path,
                modelsSymlinkPath: modelsPath,
                hubSymlinkPath: hubPath,
                progressHandler: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.progressMessage = message
                    }
                }
            )

            initializationState = .initialized
            await saveConfiguration()
            await checkSymlinkStatus()
            progressMessage = "Initialization complete!"

        } catch {
            initializationState = .error(error.localizedDescription)
            showError(message: error.localizedDescription)
        }

        isInitializing = false
    }

    // MARK: - Service Installation

    func installSystemService() async {
        guard let drive = selectedDrive else {
            showError(message: "Please select a target drive first")
            return
        }

        isInstallingService = true
        progressMessage = "Installing system service..."

        do {
            try await systemService.install(
                volumeUUID: drive.uuid,
                volumePath: drive.path
            )

            isServiceInstalled = true
            await checkServiceStatus()
            progressMessage = "System service installed!"

        } catch {
            showError(message: "Failed to install service: \(error.localizedDescription)")
        }

        isInstallingService = false
    }

    func uninstallSystemService() async {
        isInstallingService = true
        progressMessage = "Uninstalling system service..."

        do {
            try await systemService.uninstall()
            isServiceInstalled = false
            serviceStatus = [:]
            progressMessage = "System service uninstalled!"

        } catch {
            showError(message: "Failed to uninstall service: \(error.localizedDescription)")
        }

        isInstallingService = false
    }

    private func checkServiceStatus() async {
        isServiceInstalled = await systemService.isInstalled()
        serviceStatus = await systemService.getStatus()
    }

    // MARK: - Login Item

    private func loadLoginItemStatus() async {
        startAtLogin = LoginItemService.shared.isEnabled
    }

    func toggleStartAtLogin() {
        do {
            try LoginItemService.shared.toggle()
            startAtLogin = LoginItemService.shared.isEnabled
        } catch {
            showError(message: "Failed to update login item: \(error.localizedDescription)")
        }
    }

    func handleStartAtLoginChange(_ newValue: Bool) {
        guard newValue != LoginItemService.shared.isEnabled else { return }
        do {
            try LoginItemService.shared.setEnabled(newValue)
        } catch {
            // Revert the toggle if it failed
            startAtLogin = LoginItemService.shared.isEnabled
            showError(message: "Failed to update login item: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Handling

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
