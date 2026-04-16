// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Langsense",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Langsense", targets: ["Langsense"])
    ],
    targets: [
        .executableTarget(
            name: "Langsense",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "LangsenseTests",
            dependencies: ["Langsense"]
        )
    ]
)
