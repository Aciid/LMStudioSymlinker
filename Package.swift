// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LMStudioSymlinker",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LMStudioSymlinker", targets: ["LMStudioSymlinker"])
    ],
    dependencies: [
        .package(url: "https://github.com/boybeak/Tray.git", from: "0.1.0"),
        .package(url: "https://github.com/boybeak/NoLaunchWin.git", from: "0.0.1")
    ],
    targets: [
        .executableTarget(
            name: "LMStudioSymlinker",
            dependencies: ["Tray", "NoLaunchWin"],
            path: "LMStudioSymlinker",
            exclude: ["Resources/Info.plist", "Resources/LMStudioSymlinker.entitlements"]
        )
    ]
)
