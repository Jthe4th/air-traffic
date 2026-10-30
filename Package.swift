// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AirTraffic",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OverheadKit", targets: ["OverheadKit"]),
        .library(name: "OverheadUI", targets: ["OverheadUI"]),
        .executable(name: "design-preview", targets: ["DesignPreview"]),
    ],
    targets: [
        // Platform-neutral engine: feeds, geometry, routes, tracking. No UI.
        .target(name: "OverheadKit"),
        // SwiftUI views shared by tvOS / iOS / macOS.
        .target(name: "OverheadUI", dependencies: ["OverheadKit"]),
        // macOS tool that renders the TV layout to PNG, for design iteration without a tvOS simulator.
        .executableTarget(name: "DesignPreview", dependencies: ["OverheadUI", "OverheadKit"]),
        .testTarget(
            name: "OverheadKitTests",
            dependencies: ["OverheadKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
