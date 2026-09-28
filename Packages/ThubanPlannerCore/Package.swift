// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThubanPlannerCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ThubanPlannerCore", targets: ["ThubanPlannerCore"]),
    ],
    targets: [
        .target(
            name: "ThubanPlannerCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ThubanPlannerCoreTests",
            dependencies: ["ThubanPlannerCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
