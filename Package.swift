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
        ),

        // Realm for local database
        .package(
            url: "https://github.com/realm/realm-swift.git",
            from: "10.45.0"
        ),

        // SnapKit for Auto Layout
        .package(
            url: "https://github.com/SnapKit/SnapKit.git",
            from: "5.7.0"
        ),

        // Lottie for animations
        .package(
            url: "https://github.com/airbnb/lottie-ios.git",
            from: "4.3.4"
        ),

        // Kingfisher for image loading
        .package(
            url: "https://github.com/onevcat/Kingfisher.git",
            from: "7.10.1"
        ),

        // SwiftLint for code quality
        .package(
            url: "https://github.com/realm/SwiftLint.git",
            from: "0.54.0"
        ),

        // Combine Schedulers for testing
        .package(
            url: "https://github.com/pointfreeco/combine-schedulers.git",
            from: "1.0.0"
        ),

        // PromiseKit for async operations
        .package(
            url: "https://github.com/mxcl/PromiseKit.git",
            from: "8.1.1"
        ),

        // SwiftUIIntrospect for SwiftUI debugging
        .package(
            url: "https://github.com/siteline/SwiftUI-Introspect.git",
            from: "1.1.1"
        )
    ],
    targets: [
        .target(
            name: "Atlas",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "SwiftyJSON", package: "SwiftyJSON"),
                .product(name: "RealmSwift", package: "realm-swift"),
                .product(name: "SnapKit", package: "SnapKit"),
                .product(name: "Lottie", package: "lottie-ios"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "CombineSchedulers", package: "combine-schedulers"),
                .product(name: "PromiseKit", package: "PromiseKit"),
                .product(name: "SwiftUIIntrospect", package: "SwiftUI-Introspect")
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
