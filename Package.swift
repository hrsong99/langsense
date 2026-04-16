// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WrongLanguageHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WrongLanguageHelper", targets: ["WrongLanguageHelper"])
    ],
    targets: [
        .executableTarget(
            name: "WrongLanguageHelper",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "WrongLanguageHelperTests",
            dependencies: ["WrongLanguageHelper"]
        )
    ]
)
