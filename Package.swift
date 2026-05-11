// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Owlmetry",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "Owlmetry", targets: ["Owlmetry"]),
    ],
    targets: [
        .target(
            name: "Owlmetry",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(name: "OwlmetryTests", dependencies: ["Owlmetry"]),
    ]
)
