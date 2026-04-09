// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BeeterNotions",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "BeeterNotions",
            targets: ["BeeterNotions"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BeeterNotions",
            path: "Sources"
        ),
        .testTarget(
            name: "BeeterNotionsTests",
            dependencies: ["BeeterNotions"],
            path: "Tests"
        )
    ]
)
