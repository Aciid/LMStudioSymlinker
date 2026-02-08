// ConfigurationService.swift

import Foundation

actor ConfigurationService {
    static let shared = ConfigurationService()

    private let userDefaults = UserDefaults.standard
    private let configKey = "com.lmstudio.symlinker.configuration"

    // MARK: - Save/Load Configuration

    func saveConfiguration(_ config: AppConfiguration) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(config) {
            userDefaults.set(data, forKey: configKey)
        }
    }

    func loadConfiguration() -> AppConfiguration {
        guard let data = userDefaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return .default
        }
        return config
    }

    // MARK: - Individual Settings

    func setExternalDrive(path: String?, uuid: String?, name: String?) {
        var config = loadConfiguration()
        config.externalDrivePath = path
        config.externalDriveUUID = uuid
        config.externalDriveName = name
        saveConfiguration(config)
    }

    func setInitialized(_ initialized: Bool) {
        var config = loadConfiguration()
        config.isInitialized = initialized
        saveConfiguration(config)
    }

    func clearConfiguration() {
        userDefaults.removeObject(forKey: configKey)
    }
}
