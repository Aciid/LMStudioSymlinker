// OfflineModelService.swift

import Foundation

public actor OfflineModelService {
    private let fileManager = FileManager.default
    private let driveProvider: DriveProviding
    
    public init(driveProvider: DriveProviding) {
        self.driveProvider = driveProvider
    }
    
    // MARK: - Paths
    
    private var offlineModelsPath: String {
        PathHelper.lmStudioBasePath + "/offline-models"
    }
    
    private func ensureOfflineDirectoryExists() throws {
        if !fileManager.fileExists(atPath: offlineModelsPath) {
            try fileManager.createDirectory(atPath: offlineModelsPath, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Models
    
    public struct OfflineModelItem: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let publisher: String
        public let relativePath: String
        public let size: String
        public let isSynced: Bool
        public let isSyncing: Bool
        
        public init(name: String, publisher: String, relativePath: String, size: String, isSynced: Bool, isSyncing: Bool = false) {
            self.id = relativePath
            self.name = name
            self.publisher = publisher
            self.relativePath = relativePath // e.g. "publisher/repo"
            self.size = size
            self.isSynced = isSynced
            self.isSyncing = isSyncing
        }
    }
    
    // MARK: - Listing
    
    public func listModels(externalDrivePath: String) async throws -> [OfflineModelItem] {
        try ensureOfflineDirectoryExists()
        
        let externalModelsPath = externalDrivePath + "/models"
        var items: [OfflineModelItem] = []
        
        // 1. Get list of publishers (top-level directories)
        guard let publishers = try? fileManager.contentsOfDirectory(atPath: externalModelsPath) else {
            return []
        }
        
        for publisher in publishers {
            if publisher.hasPrefix(".") { continue }
            let publisherPath = externalModelsPath + "/" + publisher
            
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: publisherPath, isDirectory: &isDir), isDir.boolValue {
                // 2. Get list of repositories (models) inside publisher directory
                if let distinctModels = try? fileManager.contentsOfDirectory(atPath: publisherPath) {
                    for modelName in distinctModels {
                        if modelName.hasPrefix(".") { continue }

                        let modelPath = publisherPath + "/" + modelName
                        // Verify it's a directory (or valid model file? usually directories in LM Studio)
                        // Actually LM Studio sometimes has files at top level, but structure is usually publisher/repo.
                        // Let's treat folders as repos.
                        
                        var isModelDir: ObjCBool = false
                        if fileManager.fileExists(atPath: modelPath, isDirectory: &isModelDir), isModelDir.boolValue {
                            // Calculate size (this can be slow, maybe we should parallelize or rely on cached info later)
                            // For now, let's keep it serial but "await" capable
                            let size = await driveProvider.getStorageUsage(for: modelPath) ?? "Unknown"
                            
                            let relativePath = publisher + "/" + modelName
                            let isSynced = fileManager.fileExists(atPath: offlineModelsPath + "/" + relativePath)
                            
                            items.append(OfflineModelItem(
                                name: modelName,
                                publisher: publisher,
                                relativePath: relativePath,
                                size: size,
                                isSynced: isSynced
                            ))
                        }
                    }
                }
            }
        }
        
        // Sort by Publisher then Name
        return items.sorted {
            if $0.publisher == $1.publisher {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.publisher.localizedStandardCompare($1.publisher) == .orderedAscending
        }
    }
    
    // MARK: - Syncing
    
    public func syncModel(
        model: OfflineModelItem,
        externalDrivePath: String,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws {
        let externalPath = externalDrivePath + "/models/" + model.relativePath
        let internalPath = offlineModelsPath + "/" + model.relativePath
        
        try ensureOfflineDirectoryExists()
        
        if model.isSynced {
            // Remove (Unsync)
            progressHandler("Removing \(model.name) from offline cache...")
            if fileManager.fileExists(atPath: internalPath) {
                try fileManager.removeItem(atPath: internalPath)
            }
        } else {
            // Copy (Sync)
            progressHandler("Copying \(model.name) to offline cache...")
            
            // Ensure publisher directory exists
            let publisherPath = offlineModelsPath + "/" + model.publisher
            if !fileManager.fileExists(atPath: publisherPath) {
                try fileManager.createDirectory(atPath: publisherPath, withIntermediateDirectories: true)
            }
            
            // Just in case
            if fileManager.fileExists(atPath: internalPath) {
                try fileManager.removeItem(atPath: internalPath)
            }
            
            // Use rsync for better copying if available, else standard copy
            try await copyDirectory(from: externalPath, to: internalPath)
        }
    }
    
    private func copyDirectory(from source: String, to destination: String) async throws {
        // Shared copy logic (simplified version of SymlinkService's copy)
         let rsyncPaths = ["/usr/bin/rsync", "/opt/homebrew/bin/rsync"]
         let rsyncPath = rsyncPaths.first { fileManager.fileExists(atPath: $0) }
         
         if let rsyncPath = rsyncPath {
             let process = Process()
             process.executableURL = URL(fileURLWithPath: rsyncPath)
             process.arguments = ["-a", source + "/", destination + "/"] // trailing slash important for rsync
             
             try process.run()
             process.waitUntilExit()
             
             if process.terminationStatus == 0 { return }
         }
         
         // Fallback to FileManager
         try fileManager.copyItem(atPath: source, toPath: destination)
    }
}
