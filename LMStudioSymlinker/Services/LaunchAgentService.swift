// LaunchAgentService.swift - macOS LaunchAgents implementation of SystemServiceInstalling

import Foundation
import LMStudioSymlinkerCore

actor LaunchAgentService: SystemServiceInstalling {
    static let shared = LaunchAgentService()

    private let fileManager = FileManager.default

    private var launchAgentsPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents"
    }

    private var scriptsPath: String {
        "/usr/local/bin"
    }

    // Agent identifiers
    private let diskWatchLabel = "com.lmstudio.symlinker.disk-watch"
    private let loginLabel = "com.lmstudio.symlinker.login"
    private let pathWatchLabel = "com.lmstudio.symlinker.path-watch"
    private let logRotateLabel = "com.lmstudio.symlinker.log-rotate"

    // MARK: - Installation

    func installSystemService(volumeUUID: String, volumePath: String) async throws {
        // Create LaunchAgents directory if needed
        if !fileManager.fileExists(atPath: launchAgentsPath) {
            try fileManager.createDirectory(atPath: launchAgentsPath, withIntermediateDirectories: true)
        }

        let modelsSymlinkPath = NSHomeDirectory() + "/.lmstudio/models"
        let hubSymlinkPath = NSHomeDirectory() + "/.lmstudio/hub"
        let sourceModelsPath = volumePath + "/models"
        let sourceHubPath = volumePath + "/hub"
        let logPath = "/tmp/lmstudio-symlink-manager.log"

        // Generate and install all scripts in one privileged step (single password prompt)
        try await installAllScripts(
            volumeUUID: volumeUUID,
            volumePath: volumePath,
            modelsSymlinkPath: modelsSymlinkPath,
            hubSymlinkPath: hubSymlinkPath,
            sourceModelsPath: sourceModelsPath,
            sourceHubPath: sourceHubPath,
            logPath: logPath
        )

        // Install LaunchAgent plists
        try installLoginAgent()
        try installPathWatchAgent()
        try installDiskWatchAgent()
        try installLogRotateAgent()

        // Load the agents
        try await loadAgents()

        // Run initial check
        try await runInitialCheck()
    }

    // MARK: - Script Generation

    /// Installs all three scripts in a single privileged operation so the user is prompted for password only once.
    private func installAllScripts(
        volumeUUID: String,
        volumePath: String,
        modelsSymlinkPath: String,
        hubSymlinkPath: String,
        sourceModelsPath: String,
        sourceHubPath: String,
        logPath: String
    ) async throws {
        let mainScript = makeMainScriptContent(
            volumeUUID: volumeUUID,
            volumePath: volumePath,
            modelsSymlinkPath: modelsSymlinkPath,
            hubSymlinkPath: hubSymlinkPath,
            sourceModelsPath: sourceModelsPath,
            sourceHubPath: sourceHubPath,
            logPath: logPath
        )
        let diskWatchScript = makeDiskWatchScriptContent(logPath: logPath)
        let logRotateScript = makeLogRotateScriptContent(logPath: logPath)

        let temp1 = NSTemporaryDirectory() + UUID().uuidString + ".sh"
        let temp2 = NSTemporaryDirectory() + UUID().uuidString + ".sh"
        let temp3 = NSTemporaryDirectory() + UUID().uuidString + ".sh"

        defer {
            try? fileManager.removeItem(atPath: temp1)
            try? fileManager.removeItem(atPath: temp2)
            try? fileManager.removeItem(atPath: temp3)
        }

        try mainScript.write(to: URL(fileURLWithPath: temp1), atomically: true, encoding: .utf8)
        try diskWatchScript.write(to: URL(fileURLWithPath: temp2), atomically: true, encoding: .utf8)
        try logRotateScript.write(to: URL(fileURLWithPath: temp3), atomically: true, encoding: .utf8)

        let mainDest = "\(scriptsPath)/lmstudio-symlink-manager.sh"
        let diskWatchDest = "\(scriptsPath)/lmstudio-disk-watch.sh"
        let logRotateDest = "\(scriptsPath)/lmstudio-log-rotate.sh"

        let shellCommand = """
            mkdir -p \(scriptsPath) && \
            cp '\(temp1)' '\(mainDest)' && \
            cp '\(temp2)' '\(diskWatchDest)' && \
            cp '\(temp3)' '\(logRotateDest)' && \
            chmod +x '\(mainDest)' '\(diskWatchDest)' '\(logRotateDest)'
            """

        let script = "do shell script \"\(shellCommand.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

        let terminationStatus: Int32 = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }

        if terminationStatus != 0 {
            throw SymlinkService.SymlinkError.copyFailed("Failed to install scripts via osascript")
        }
    }

    private func makeMainScriptContent(
        volumeUUID: String,
        volumePath: String,
        modelsSymlinkPath: String,
        hubSymlinkPath: String,
        sourceModelsPath: String,
        sourceHubPath: String,
        logPath: String
    ) -> String {
        """
        #!/bin/zsh
        # /usr/local/bin/lmstudio-symlink-manager.sh
        # Manages LM Studio symlinks based on external drive mount status

        VOLUME_UUID=\(shellEscape(volumeUUID))
        VOLUME_PATH=\(shellEscape(volumePath))
        SYMLINK_PATH_MODELS=\(shellEscape(modelsSymlinkPath))
        SOURCE_PATH_MODELS=\(shellEscape(sourceModelsPath))
        SYMLINK_PATH_HUB=\(shellEscape(hubSymlinkPath))
        SOURCE_PATH_HUB=\(shellEscape(sourceHubPath))
        LOG=\(shellEscape(logPath))

        log() {
            echo "$(date): $1" >> "$LOG"
        }

        is_mounted() {
            diskutil info "$VOLUME_UUID" &>/dev/null && \\
            [[ -d "$VOLUME_PATH" ]]
        }

        create_symlink() {
            local symlink="$1"
            local source="$2"
            local name="$3"

            if [[ -z "$symlink" || "$symlink" == "/" ]]; then
                log "ERROR: Symlink path is empty or root for $name. Aborting."
                return 1
            fi

            if [[ ! -d "$source" ]]; then
                log "ERROR: Source $source does not exist for $name. Skipping."
                return 1
            fi

            # If symlink already exists and points to the correct target, do nothing
            if [[ -L "$symlink" ]]; then
                local current_target
                current_target=$(readlink "$symlink" 2>/dev/null)
                if [[ "$current_target" == "$source" ]]; then
                    log "[$name] Already linked: $symlink -> $source"
                    return 0
                fi
                rm "$symlink"
                log "[$name] Removed old symlink (was -> $current_target)"
            elif [[ -d "$symlink" ]]; then
                mv "$symlink" "${symlink}_backup_$(date +%s)"
                log "[$name] Backed up existing directory"
            fi

            mkdir -p "$(dirname "$symlink")"
            ln -s "$source" "$symlink"
            log "[$name] Created symlink: $symlink -> $source"
        }

        remove_symlink() {
            local symlink="$1"
            local name="$2"

            if [[ -L "$symlink" ]]; then
                rm "$symlink"
                log "[$name] Removed broken symlink"
                mkdir -p "$symlink"
                log "[$name] Created empty placeholder directory"
            fi
        }

        # Main logic
        if is_mounted; then
            log "Volume $VOLUME_PATH is mounted"
            create_symlink "$SYMLINK_PATH_MODELS" "$SOURCE_PATH_MODELS" "models"
            create_symlink "$SYMLINK_PATH_HUB" "$SOURCE_PATH_HUB" "hub"
        else
            log "Volume $VOLUME_PATH is NOT mounted"
            remove_symlink "$SYMLINK_PATH_MODELS" "models"
            remove_symlink "$SYMLINK_PATH_HUB" "hub"
        fi
        """
    }

    private func makeDiskWatchScriptContent(logPath: String) -> String {
        """
        #!/bin/zsh
        # /usr/local/bin/lmstudio-disk-watch.sh
        # Watches for disk mount/unmount events and triggers the symlink manager

        LOG="\(logPath)"
        SCRIPT="/usr/local/bin/lmstudio-symlink-manager.sh"

        echo "$(date): disk-watch started" >> "$LOG"

        # Check if fswatch is available
        if ! command -v fswatch &>/dev/null; then
            echo "$(date): fswatch not found, using fallback polling" >> "$LOG"
            while true; do
                /bin/zsh "$SCRIPT"
                sleep 5
            done
        else
            # Monitor /Volumes for changes
            fswatch -0 --event Created --event Removed /Volumes | while read -d '' event; do
                echo "$(date): Volume change detected: $event" >> "$LOG"
                sleep 2  # Allow mount to fully complete
                /bin/zsh "$SCRIPT"
            done
        fi
        """
    }

    private func makeLogRotateScriptContent(logPath: String) -> String {
        """
        #!/bin/zsh
        # /usr/local/bin/lmstudio-log-rotate.sh
        # Log rotation for LM Studio symlink manager

        LOG="\(logPath)"
        MAX_SIZE=1048576  # 1MB in bytes

        if [[ -f "$LOG" ]]; then
            FILE_SIZE=$(stat -f%z "$LOG" 2>/dev/null || echo 0)
            if (( FILE_SIZE > MAX_SIZE )); then
                mv "$LOG" "${LOG}.old"
                echo "$(date): Log rotated" > "$LOG"
            fi
        fi
        """
    }

    // MARK: - LaunchAgent Plists

    private func installLoginAgent() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(loginLabel)</string>

            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/lmstudio-symlink-manager.sh</string>
            </array>

            <key>RunAtLoad</key>
            <true/>

            <key>StandardOutPath</key>
            <string>/tmp/lmstudio-symlink-login.stdout.log</string>

            <key>StandardErrorPath</key>
            <string>/tmp/lmstudio-symlink-login.stderr.log</string>
        </dict>
        </plist>
        """

        try plist.write(toFile: "\(launchAgentsPath)/\(loginLabel).plist", atomically: true, encoding: .utf8)
    }

    private func installPathWatchAgent() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(pathWatchLabel)</string>

            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/lmstudio-symlink-manager.sh</string>
            </array>

            <key>WatchPaths</key>
            <array>
                <string>/Volumes</string>
            </array>

            <key>StandardOutPath</key>
            <string>/tmp/lmstudio-symlink-pathwatch.stdout.log</string>

            <key>StandardErrorPath</key>
            <string>/tmp/lmstudio-symlink-pathwatch.stderr.log</string>
        </dict>
        </plist>
        """

        try plist.write(toFile: "\(launchAgentsPath)/\(pathWatchLabel).plist", atomically: true, encoding: .utf8)
    }

    private func installDiskWatchAgent() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(diskWatchLabel)</string>

            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/lmstudio-disk-watch.sh</string>
            </array>

            <key>RunAtLoad</key>
            <true/>

            <key>KeepAlive</key>
            <true/>

            <key>StandardOutPath</key>
            <string>/tmp/lmstudio-disk-watch.stdout.log</string>

            <key>StandardErrorPath</key>
            <string>/tmp/lmstudio-disk-watch.stderr.log</string>
        </dict>
        </plist>
        """

        try plist.write(toFile: "\(launchAgentsPath)/\(diskWatchLabel).plist", atomically: true, encoding: .utf8)
    }

    private func installLogRotateAgent() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(logRotateLabel)</string>

            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/lmstudio-log-rotate.sh</string>
            </array>

            <key>StartCalendarInterval</key>
            <dict>
                <key>Hour</key>
                <integer>3</integer>
                <key>Minute</key>
                <integer>0</integer>
            </dict>

            <key>StandardOutPath</key>
            <string>/tmp/lmstudio-logrotate.stdout.log</string>

            <key>StandardErrorPath</key>
            <string>/tmp/lmstudio-logrotate.stderr.log</string>
        </dict>
        </plist>
        """

        try plist.write(toFile: "\(launchAgentsPath)/\(logRotateLabel).plist", atomically: true, encoding: .utf8)
    }

    // MARK: - Agent Management

    private func loadAgents() async throws {
        let labels = [loginLabel, pathWatchLabel, diskWatchLabel, logRotateLabel]
        let uid = getuid()

        for label in labels {
            let plistPath = "\(launchAgentsPath)/\(label).plist"

            // Unload first if already loaded
            _ = await runLaunchctl(["bootout", "gui/\(uid)/\(label)"])

            // Load the agent
            _ = await runLaunchctl(["bootstrap", "gui/\(uid)", plistPath])
        }
    }

    private func runLaunchctl(_ arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    private func runInitialCheck() async throws {
        let path = "\(scriptsPath)/lmstudio-symlink-manager.sh"
        let terminationStatus: Int32 = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [path]

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }

        if terminationStatus != 0 {
            throw SymlinkService.SymlinkError.copyFailed("Failed to install scripts via osascript")
        }
    }

    // MARK: - Uninstallation

    func uninstallSystemService() async throws {
        let uid = getuid()
        let labels = [loginLabel, pathWatchLabel, diskWatchLabel, logRotateLabel]

        // Unload agents
        for label in labels {
            _ = await runLaunchctl(["bootout", "gui/\(uid)/\(label)"])
        }

        // Remove plist files
        for label in labels {
            let plistPath = "\(launchAgentsPath)/\(label).plist"
            try? fileManager.removeItem(atPath: plistPath)
        }

        // Remove scripts (requires admin)
        let scripts = [
            "lmstudio-symlink-manager.sh",
            "lmstudio-disk-watch.sh",
            "lmstudio-log-rotate.sh"
        ]

        let scriptPaths = scripts.map { "\(scriptsPath)/\($0)" }.joined(separator: " ")
        let script = "do shell script \"rm -f \(scriptPaths)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        try? process.run()
        process.waitUntilExit()

        // Clean up logs
        let logs = [
            "/tmp/lmstudio-symlink-manager.log",
            "/tmp/lmstudio-symlink-manager.log.old",
            "/tmp/lmstudio-disk-watch.stdout.log",
            "/tmp/lmstudio-disk-watch.stderr.log",
            "/tmp/lmstudio-symlink-login.stdout.log",
            "/tmp/lmstudio-symlink-login.stderr.log",
            "/tmp/lmstudio-symlink-pathwatch.stdout.log",
            "/tmp/lmstudio-symlink-pathwatch.stderr.log",
            "/tmp/lmstudio-logrotate.stdout.log",
            "/tmp/lmstudio-logrotate.stderr.log"
        ]

        for log in logs {
            try? fileManager.removeItem(atPath: log)
        }
    }

    // MARK: - Status Check

    func isServiceInstalled() -> Bool {
        let plistPath = "\(launchAgentsPath)/\(loginLabel).plist"
        return fileManager.fileExists(atPath: plistPath)
    }

    func getServiceStatus() async -> [String: Bool] {
        let uid = getuid()
        let labels = [
            ("Login", loginLabel),
            ("Path Watch", pathWatchLabel),
            ("Disk Watch", diskWatchLabel),
            ("Log Rotate", logRotateLabel)
        ]

        var status: [String: Bool] = [:]

        for (name, label) in labels {
            let isRunning = await checkAgentRunning(label: label, uid: uid)
            status[name] = isRunning
        }

        return status
    }

    private func checkAgentRunning(label: String, uid: uid_t) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["print", "gui/\(uid)/\(label)"]
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - SystemServiceInstalling

    public func install(volumeUUID: String, volumePath: String) async throws {
        try await installSystemService(volumeUUID: volumeUUID, volumePath: volumePath)
    }

    public func uninstall() async throws {
        try await uninstallSystemService()
    }

    public func isInstalled() async -> Bool {
        isServiceInstalled()
    }

    public func getStatus() async -> [String: Bool] {
        await getServiceStatus()
    }
}

private func shellEscape(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
