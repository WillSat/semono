// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Semono",
    platforms: [
        .macOS(.v26)
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
        ),
        .executableTarget(
            name: "gpu_helper",
            path: "HelpersGpu",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "disk_helper",
            path: "HelpersDisk",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
