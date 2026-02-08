// SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                Divider()

                // Drive Selection
                driveSelectionSection

                // Storage Info
                storageInfoSection

                // Symlink Status
                symlinkStatusSection

                // Progress
                if !viewModel.progressMessage.isEmpty {
                    progressSection
                }

                Divider()

                // Actions
                actionsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 400)
        }
        .frame(minWidth: 500, minHeight: 650)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("LM Studio Symlinker")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch viewModel.initializationState {
        case .uninitialized:
            return .orange
        case .initialized:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch viewModel.initializationState {
        case .uninitialized:
            return "Uninitialized"
        case .initialized:
            return "Initialized"
        case .error:
            return "Error"
        }
    }

    // MARK: - Drive Selection

    private var driveSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target Drive")
                .font(.headline)

            HStack {
                if let drive = viewModel.selectedDrive {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.fill")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(drive.name)
                                .fontWeight(.medium)

                            Text(drive.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("No drive selected")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { viewModel.openDrivePicker() }) {
                    Label(
                        viewModel.selectedDrive == nil ? "Select Target Disk" : "Change",
                        systemImage: "folder"
                    )
                }
                .disabled(viewModel.isInitializing)
            }

            // Drive picker dropdown for available drives
            if !viewModel.availableDrives.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available External Drives:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.availableDrives, id: \.uuid) { drive in
                        DriveRowView(
                            drive: drive,
                            isSelected: viewModel.selectedDrive?.uuid == drive.uuid
                        ) {
                            Task {
                                await viewModel.selectDrive(drive)
                            }
                        }
                    }
                }
            } else if viewModel.isLoadingDrives {
                ProgressView("Loading drives...")
                    .font(.caption)
            } else {
                Text("No external drives found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Refresh Drives") {
                Task {
                    await viewModel.refreshDriveList()
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    // MARK: - Storage Info

    private var storageInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage Information")
                .font(.headline)

            if viewModel.selectedDrive != nil {
                Button(action: openTargetDiskInFinder) {
                    StorageInfoRow(
                        label: "Target disk usage",
                        value: viewModel.targetDiskStorageUsage,
                        icon: "externaldrive"
                    )
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
            }

            if viewModel.isLMStudioModelsExist {
                Button(action: openLMStudioFolderInFinder) {
                    StorageInfoRow(
                        label: "LM Studio models",
                        value: viewModel.lmStudioModelsUsage.isEmpty ? "Calculating..." : viewModel.lmStudioModelsUsage,
                        icon: "doc.on.doc"
                    )
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
            }
        }
    }

    private func openTargetDiskInFinder() {
        guard let path = viewModel.selectedDrive?.path else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    private func openLMStudioFolderInFinder() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".lmstudio")
        let url = URL(fileURLWithPath: path, isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    // MARK: - Symlink Status

    @ViewBuilder
    private var symlinkStatusSection: some View {
        if let status = viewModel.symlinkStatus {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Current Status")
                        .font(.headline)
                    Spacer()
                    Button("Refresh status") {
                        Task {
                            await viewModel.refreshStatus()
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                SymlinkStatusRow(
                    label: "~/.lmstudio/models",
                    pathType: status.modelsPathType
                )

                SymlinkStatusRow(
                    label: "~/.lmstudio/hub",
                    pathType: status.hubPathType
                )
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        HStack {
            if viewModel.isInitializing || viewModel.isInstallingService {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text(viewModel.progressMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Initialize Button
            Button(action: {
                Task {
                    await viewModel.initialize()
                }
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Initialize")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canInitialize)

            // System Service description and button
            Text("The system service keeps LM Studio’s models and hub symlinks in sync with your external drive: it runs once at login, reacts when you plug or unplug the drive (via /Volumes), and keeps a background watcher. Logs are written to /tmp and rotated daily.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await viewModel.installSystemService()
                    }
                }) {
                    HStack {
                        Image(systemName: "gearshape.2")
                        Text("Install System Service")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.canInstallService)

                if viewModel.isServiceInstalled {
                    Button(role: .destructive, action: {
                        Task {
                            await viewModel.uninstallSystemService()
                        }
                    }) {
                        Image(systemName: "trash")
                    }
                }
            }

            // Service Status
            if viewModel.isServiceInstalled {
                ServiceStatusView(status: viewModel.serviceStatus)
            }

            Divider()

            // Login Item Toggle
            Toggle(isOn: $viewModel.startAtLogin) {
                Label("Start at Login", systemImage: "power")
            }
            .toggleStyle(.switch)
            .onChange(of: viewModel.startAtLogin) { _, newValue in
                viewModel.handleStartAtLoginChange(newValue)
            }
        }
    }
}

// MARK: - Supporting Views

struct DriveRowView: View {
    let drive: DriveInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: drive.isRemovable ? "externaldrive.fill.badge.exclamationmark" : "externaldrive.fill")
                    .foregroundStyle(isSelected ? .white : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.name)
                        .fontWeight(.medium)
                    Text(drive.path)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                }
            }
            .padding(8)
            .background(isSelected ? Color.blue : Color.gray.opacity(0.1))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct StorageInfoRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

struct SymlinkStatusRow: View {
    let label: String
    let pathType: PathType

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(label)
                .font(.callout.monospaced())

            Spacer()

            Text(statusText)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(iconColor.opacity(0.1))
                .foregroundStyle(iconColor)
                .clipShape(Capsule())
        }
    }

    private var icon: String {
        switch pathType {
        case .symlink:
            return "link"
        case .realDirectory:
            return "folder.fill"
        case .file:
            return "doc.fill"
        case .doesNotExist:
            return "xmark.circle"
        }
    }

    private var iconColor: Color {
        switch pathType {
        case .symlink:
            return .green
        case .realDirectory:
            return .orange
        case .file:
            return .yellow
        case .doesNotExist:
            return .gray
        }
    }

    private var statusText: String {
        switch pathType {
        case .symlink(let target):
            let shortTarget = (target as NSString).lastPathComponent
            return "Symlink → …/\(shortTarget)"
        case .realDirectory:
            return "Real Directory"
        case .file:
            return "File"
        case .doesNotExist:
            return "Does Not Exist"
        }
    }
}

struct ServiceStatusView: View {
    let status: [String: Bool]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Service Status")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(Array(status.keys.sorted()), id: \.self) { key in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(status[key] == true ? Color.green : Color.red)
                            .frame(width: 6, height: 6)

                        Text(key)
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel())
    }
}
#endif
