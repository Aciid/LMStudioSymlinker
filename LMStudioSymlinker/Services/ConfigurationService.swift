// ConfigurationService.swift - macOS UserDefaults implementation of ConfigStorage

import Foundation
import LMStudioSymlinkerCore

actor ConfigurationService: ConfigStorage {
    static let shared = ConfigurationService()

    private let userDefaults = UserDefaults.standard
    private let configKey = "com.lmstudio.symlinker.configuration"

    // MARK: - Save/Load Configuration (ConfigStorage)

    func saveConfiguration(_ config: AppConfiguration) async {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(config) {
            userDefaults.set(data, forKey: configKey)
        }
    }

    func loadConfiguration() async -> AppConfiguration {
        guard let data = userDefaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return .default
        }
        return config
    }

    // MARK: - Individual Settings

    func setExternalDrive(path: String?, uuid: String?, name: String?) async {
        var config = await loadConfiguration()
        config.externalDrivePath = path
        config.externalDriveUUID = uuid
        config.externalDriveName = name
        await saveConfiguration(config)
    }

    func setInitialized(_ initialized: Bool) async {
        var config = await loadConfiguration()
        config.isInitialized = initialized
        await saveConfiguration(config)
    }

    func clearConfiguration() {
        userDefaults.removeObject(forKey: configKey)
    }
}
