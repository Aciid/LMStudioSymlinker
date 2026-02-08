// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LMStudioSymlinker",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "LMStudioSymlinkerCore", targets: ["LMStudioSymlinkerCore"]),
        .executable(name: "LMStudioSymlinker", targets: ["LMStudioSymlinker"]),
        .executable(name: "LMStudioSymlinkerCLI", targets: ["LMStudioSymlinkerCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/boybeak/Tray.git", from: "0.1.0"),
        .package(url: "https://github.com/boybeak/NoLaunchWin.git", from: "0.0.1")
    ],
    targets: [
        .target(
            name: "LMStudioSymlinkerCore",
            path: "LMStudioSymlinkerCore"
        ),
        .executableTarget(
            name: "LMStudioSymlinker",
            dependencies: ["LMStudioSymlinkerCore", "Tray", "NoLaunchWin"],
            path: "LMStudioSymlinker",
            exclude: ["Resources/Info.plist", "Resources/LMStudioSymlinker.entitlements"]
        ),
        .executableTarget(
            name: "LMStudioSymlinkerCLI",
            dependencies: ["LMStudioSymlinkerCore"],
            path: "LMStudioSymlinkerCLI",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
