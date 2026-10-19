// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlainParse",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlainParse", targets: ["PlainParse"]),
    ],
    targets: [
        .target(name: "PlainParse"),
        .testTarget(name: "PlainParseTests", dependencies: ["PlainParse"]),
    ]
)
