// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AkiAPI",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15)
    ],
    products: [
        .library(name: "AkiAPI", targets: ["AkiAPI"])
    ],
    targets: [
        .target(name: "AkiAPI"),
        .testTarget(name: "AkiAPITests", dependencies: ["AkiAPI"])
    ]
)
