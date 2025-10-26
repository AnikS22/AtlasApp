// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Atlas",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Atlas",
            targets: ["Atlas"]
        ),
    ],
    dependencies: [
        // Alamofire for networking (OAuth APIs: Gmail, Drive, Slack, etc.)
        .package(
            url: "https://github.com/Alamofire/Alamofire.git",
            from: "5.8.1"
        ),

        // KeychainAccess for secure storage
        .package(
            url: "https://github.com/kishikawakatsumi/KeychainAccess.git",
            from: "4.2.2"
        ),

        // SQLite for local encrypted database
        .package(
            url: "https://github.com/stephencelis/SQLite.swift.git",
            from: "0.15.0"
        ),

        // SwiftyJSON for JSON parsing
        .package(
            url: "https://github.com/SwiftyJSON/SwiftyJSON.git",
            from: "5.0.1"
        )
    ],
    targets: [
        .target(
            name: "Atlas",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "SwiftyJSON", package: "SwiftyJSON")
            ],
            path: "Sources/Atlas"
        ),
        .testTarget(
            name: "AtlasTests",
            dependencies: ["Atlas"],
            path: "Tests/AtlasTests"
        ),
    ]
)
