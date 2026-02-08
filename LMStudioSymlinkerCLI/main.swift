// LMStudioSymlinkerCLI - Linux CLI entry
import Foundation
import LMStudioSymlinkerCore

@main
struct CLI {
    static func main() async {
        #if os(Linux)
        let args = CommandLine.arguments
        let subcommand = args.count > 1 ? args[1] : "status"

        let config = FileConfigStorage()
        let driveProvider = LinuxDiskService()
        let symlinkService = SymlinkService(driveProvider: driveProvider)
        let systemService = SystemdUserService()

        switch subcommand {
        case "status":
            await status(config: config, driveProvider: driveProvider, systemService: systemService)
        case "configure":
            await configure(config: config, driveProvider: driveProvider, args: args)
        case "init":
            await runInit(config: config, driveProvider: driveProvider, symlinkService: symlinkService)
        case "service":
            if args.count > 2 {
                switch args[2] {
                case "install":
                    await serviceInstall(config: config, driveProvider: driveProvider, systemService: systemService)
                case "uninstall":
                    await serviceUninstall(systemService: systemService)
                default:
                    print("Unknown: service \(args[2]). Use: install | uninstall")
                }
            } else {
                print("Usage: LMStudioSymlinkerCLI service [install | uninstall]")
            }
        default:
            print("LM Studio Symlinker CLI")
            print("Usage: LMStudioSymlinkerCLI [status | configure | init | service install | service uninstall]")
        }
        #else
        print("LM Studio Symlinker CLI is intended for Linux. On macOS, use the LMStudioSymlinker app.")
        #endif
    }

    #if os(Linux)
    static func status(config: FileConfigStorage, driveProvider: DriveProviding, systemService: SystemdUserService) async {
        let loaded = await config.loadConfiguration()
        print("Target drive: \(loaded.externalDrivePath ?? "(none)")")
        print("Initialized: \(loaded.isInitialized)")

        let status = await driveProvider.getSymlinkStatus()
        print("~/.lmstudio/models: \(describe(status.modelsPathType))")
        print("~/.lmstudio/hub: \(describe(status.hubPathType))")

        let installed = await systemService.isInstalled()
        print("System service: \(installed ? "installed" : "not installed")")
        if installed {
            let st = await systemService.getStatus()
            for (k, v) in st.sorted(by: { $0.key < $1.key }) {
                print("  \(k): \(v ? "ok" : "inactive")")
            }
        }
    }

    static func describe(_ pathType: PathType) -> String {
        switch pathType {
        case .symlink(let target):
            return "symlink → \(target)"
        case .realDirectory:
            return "directory"
        case .file:
            return "file"
        case .doesNotExist:
            return "missing"
        }
    }

    static func configure(config: FileConfigStorage, driveProvider: DriveProviding, args: [String]) async {
        let path: String?
        if let idx = args.firstIndex(of: "--drive"), idx + 1 < args.count {
            path = args[idx + 1]
        } else {
            print("Available drives:")
            let drives = (try? await driveProvider.getExternalDrives()) ?? []
            for (i, d) in drives.enumerated() {
                print("  \(i + 1). \(d.name)  \(d.path)")
            }
            if drives.isEmpty {
                print("  (none found under /media, /run/media, /mnt)")
                return
            }
            print("Enter path or number (e.g. /media/<user>/MyDrive):")
            guard let line = readLine()?.trimmingCharacters(in: .whitespaces), !line.isEmpty else { return }
            if let num = Int(line), num >= 1, num <= drives.count {
                path = drives[num - 1].path
            } else {
                path = line
            }
        }

        guard let path = path else {
            print("No path given.")
            return
        }

        guard let info = await driveProvider.getDriveInfo(for: path) else {
            print("Path not found or not a valid mount: \(path)")
            return
        }

        var loaded = await config.loadConfiguration()
        loaded.externalDrivePath = info.path
        loaded.externalDriveUUID = info.uuid
        loaded.externalDriveName = info.name
        await config.saveConfiguration(loaded)
        print("Configured target drive: \(info.path)")
    }

    static func runInit(config: FileConfigStorage, driveProvider: DriveProviding, symlinkService: SymlinkService) async {
        let loaded = await config.loadConfiguration()
        guard let path = loaded.externalDrivePath else {
            print("Run 'configure' first to set the target drive.")
            return
        }

        let modelsPath = driveProvider.modelsSymlinkPath
        let hubPath = driveProvider.hubSymlinkPath

        print("Initializing symlinks for \(path)...")
        do {
            try await symlinkService.initialize(
                volumePath: path,
                modelsSymlinkPath: modelsPath,
                hubSymlinkPath: hubPath,
                progressHandler: { print($0) }
            )
            var updated = await config.loadConfiguration()
            updated.isInitialized = true
            await config.saveConfiguration(updated)
            print("Done.")
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    static func serviceInstall(config: FileConfigStorage, driveProvider: DriveProviding, systemService: SystemdUserService) async {
        let loaded = await config.loadConfiguration()
        guard let path = loaded.externalDrivePath else {
            print("Run 'configure' and 'init' first.")
            return
        }

        print("Installing systemd user service...")
        do {
            try await systemService.install(volumeUUID: loaded.externalDriveUUID ?? path, volumePath: path)
            print("Service installed. Symlinks will be updated at login and when the drive is mounted.")
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    static func serviceUninstall(systemService: SystemdUserService) async {
        do {
            try await systemService.uninstall()
            print("Service uninstalled.")
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
    #endif
}
