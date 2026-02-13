// ConfigStorage.swift - Platform-agnostic config persistence

import Foundation

/// Persists and retrieves the application configuration.
///
/// Implementations must be `Sendable` so they can safely be shared across
/// isolation boundaries. On macOS the default implementation uses
/// `UserDefaults`; on Linux a JSON file under `XDG_CONFIG_HOME` is used.
public protocol ConfigStorage: Sendable {
    /// Loads the stored configuration, returning ``AppConfiguration/default``
    /// when no previous configuration exists.
    func loadConfiguration() async -> AppConfiguration

    /// Persists the given configuration, replacing any previously saved state.
    func saveConfiguration(_ config: AppConfiguration) async
}
