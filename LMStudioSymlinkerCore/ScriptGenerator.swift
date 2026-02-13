// ScriptGenerator.swift - Shell script template generation for LaunchAgents

import Foundation

/// Generates shell scripts used by the macOS LaunchAgent-based system service.
///
/// Extracted from `LaunchAgentService` to keep script templates testable in
/// isolation and to reduce the size of the service actor.
public enum ScriptGenerator {

    // MARK: - Shell Escaping

    /// Wraps a value in single quotes, escaping embedded single quotes.
    ///
    /// Example: `My Drive` → `'My Drive'`, `it's` → `'it'\''s'`
    public static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Main Symlink Manager Script

    /// Returns the content of `lmstudio-symlink-manager.sh`.
    ///
    /// The script checks whether the configured volume is mounted and creates
    /// or removes symlinks accordingly. All interpolated values are shell-escaped.
    ///
    /// - Parameters:
    ///   - volumeUUID: The UUID used to query `diskutil info`.
    ///   - volumePath: The expected mount point (e.g. `/Volumes/MyDrive`).
    ///   - modelsSymlinkPath: Destination for the models symlink.
    ///   - hubSymlinkPath: Destination for the hub symlink.
    ///   - sourceModelsPath: Source models directory on the external drive.
    ///   - sourceHubPath: Source hub directory on the external drive.
    ///   - logPath: Path to the log file.
    public static func mainScript(
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

    // MARK: - Disk Watch Script

    /// Returns the content of `lmstudio-disk-watch.sh`.
    ///
    /// The script monitors `/Volumes` for mount/unmount events using `fswatch`
    /// (if available) or a 5-second polling fallback, and triggers the main
    /// symlink manager script on each change.
    ///
    /// - Parameter logPath: Path to the log file.
    public static func diskWatchScript(logPath: String) -> String {
        """
        #!/bin/zsh
        # /usr/local/bin/lmstudio-disk-watch.sh
        # Watches for disk mount/unmount events and triggers the symlink manager

        LOG=\(shellEscape(logPath))
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

    // MARK: - Log Rotate Script

    /// Returns the content of `lmstudio-log-rotate.sh`.
    ///
    /// Rotates the log file when it exceeds 1 MB.
    ///
    /// - Parameter logPath: Path to the log file.
    public static func logRotateScript(logPath: String) -> String {
        """
        #!/bin/zsh
        # /usr/local/bin/lmstudio-log-rotate.sh
        # Log rotation for LM Studio symlink manager

        LOG=\(shellEscape(logPath))
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
}
