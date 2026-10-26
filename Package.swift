// swift-tools-version:5.9
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
            // On for `swift test`, so the clean-up tests compile.
            // scripts/build-local.sh does not pass this flag. scripts/build-dev.sh does.
            swiftSettings: [.define("ZAPBAR_ADVANCED")],
            linkerSettings: [.linkedLibrary("z")]
        ),
        .testTarget(
            name: "TvRemoteCoreTests",
            dependencies: ["TvRemoteCore"],
            path: "Tests/TvRemoteCoreTests"
        )
    ]
)
