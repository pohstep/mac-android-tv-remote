// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "PohstepRemote",
    products: [
        .library(name: "TvRemoteCore", targets: ["TvRemoteCore"])
    ],
    targets: [
        .target(
            name: "TvRemoteCore",
            path: "Sources/TvRemoteCore",
            resources: [
                .copy("Resources/never-touch.json"),
                .copy("Resources/cleanup-preview.json")
            ],
            // On for `swift test`, so clean-up and the v1 migration tests compile.
            // scripts/build-local.sh does not pass these flags. scripts/build-dev.sh does.
            swiftSettings: [
                .define("ZAPBAR_ADVANCED"),
                .define("ZAPBAR_MIGRATE_V1")
            ],
            linkerSettings: [.linkedLibrary("z")]
        ),
        .testTarget(
            name: "TvRemoteCoreTests",
            dependencies: ["TvRemoteCore"],
            path: "Tests/TvRemoteCoreTests"
        )
    ]
)
