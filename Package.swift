// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CatsAndDogsPeek",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CatsAndDogsPeek",
            resources: [
                .copy("Resources/species")
            ]
        )
    ]
)
