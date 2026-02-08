// PathHelper.swift - Shared path helpers (platform-agnostic)

import Foundation

public enum PathHelper {
    public static var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    public static var lmStudioBasePath: String {
        homeDirectory + "/.lmstudio"
    }

    public static var modelsSymlinkPath: String {
        lmStudioBasePath + "/models"
    }

    public static var hubSymlinkPath: String {
        lmStudioBasePath + "/hub"
    }
}
