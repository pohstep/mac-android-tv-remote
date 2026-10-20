// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PohstepRemote",
    products: [
        .library(name: "TvRemoteCore", targets: ["TvRemoteCore"])
    ],
    targets: [
        .target(name: "TvRemoteCore", path: "Sources/TvRemoteCore"),
        .testTarget(
            name: "TvRemoteCoreTests",
            dependencies: ["TvRemoteCore"],
            path: "Tests/TvRemoteCoreTests"
        )
    ]
)
