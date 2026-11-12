// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WTidy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WTidy",
            path: "Sources/WTidy",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "WTidyTests",
            dependencies: ["WTidy"],
            path: "Tests/WTidyTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
