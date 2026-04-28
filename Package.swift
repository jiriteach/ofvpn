// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FortiVPNMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FortiVPNMenuBar", targets: ["FortiVPNMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "FortiVPNMenuBar",
            path: "Sources/FortiVPNMenuBar"
        )
    ]
)
