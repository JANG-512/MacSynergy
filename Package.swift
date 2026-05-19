// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacSynergy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacSynergy", targets: ["MacSynergy"])
    ],
    targets: [
        .executableTarget(
            name: "MacSynergy",
            path: "Sources"
        )
    ]
)
