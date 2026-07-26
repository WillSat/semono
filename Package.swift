// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Semono",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Semono", targets: ["Semono"])
    ],
    targets: [
        .executableTarget(
            name: "Semono",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("CoreWLAN")
            ]
        ),
        .executableTarget(
            name: "power_helper",
            path: "Helpers",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
