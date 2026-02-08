// ConfigStorage.swift - Platform-agnostic config persistence

import Foundation

public protocol ConfigStorage: Sendable {
    func loadConfiguration() async -> AppConfiguration
    func saveConfiguration(_ config: AppConfiguration) async
}

