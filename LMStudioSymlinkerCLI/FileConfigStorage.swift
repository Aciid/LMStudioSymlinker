#if os(Linux)
import Foundation
import LMStudioSymlinkerCore

/// ConfigStorage implementation using a JSON file under XDG_CONFIG_HOME.
public final class FileConfigStorage: ConfigStorage, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager = FileManager.default

    public init(configDirectory: URL? = nil) {
        let dir = configDirectory ?? Self.defaultConfigDirectory
        self.fileURL = dir.appendingPathComponent("config.json", isDirectory: false)
    }

    private static var defaultConfigDirectory: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("lmstudio-symlinker", isDirectory: true)
        }
        return URL(fileURLWithPath: PathHelper.homeDirectory)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("lmstudio-symlinker", isDirectory: true)
    }

    public func loadConfiguration() async -> AppConfiguration {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return .default
        }
        return config
    }

    public func saveConfiguration(_ config: AppConfiguration) async {
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: fileURL)
        }
    }
}
#endif
