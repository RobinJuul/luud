// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Luud",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "Luud",
            path: "Sources/Luud",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
