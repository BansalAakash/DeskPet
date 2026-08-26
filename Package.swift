// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeskPet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DeskPet",
            resources: [
                .copy("Resources/species")
            ]
        )
    ]
)
