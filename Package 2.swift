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
        // OpenAI Swift SDK
        .package(
            url: "https://github.com/MacPaw/OpenAI.git",
            from: "0.2.4"
        ),

        // Alamofire for networking
        .package(
            url: "https://github.com/Alamofire/Alamofire.git",
            from: "5.8.1"
        ),

        // KeychainAccess for secure storage
        .package(
            url: "https://github.com/kishikawakatsumi/KeychainAccess.git",
            from: "4.2.2"
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

        // Socket.IO for real-time communication
        .package(
            url: "https://github.com/socketio/socket.io-client-swift.git",
            from: "16.1.0"
        ),

        // SwiftUIIntrospect for SwiftUI debugging
        .package(
            url: "https://github.com/siteline/SwiftUI-Introspect.git",
            from: "1.1.1"
        ),

        // Firebase for analytics and crash reporting
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            from: "10.20.0"
        ),

        // Sentry for error tracking
        .package(
            url: "https://github.com/getsentry/sentry-cocoa.git",
            from: "8.17.2"
        )
    ],
    targets: [
        .target(
            name: "Atlas",
            dependencies: [
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "SwiftyJSON", package: "SwiftyJSON"),
                .product(name: "RealmSwift", package: "realm-swift"),
                .product(name: "SnapKit", package: "SnapKit"),
                .product(name: "Lottie", package: "lottie-ios"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "CombineSchedulers", package: "combine-schedulers"),
                .product(name: "PromiseKit", package: "PromiseKit"),
                .product(name: "SocketIO", package: "socket.io-client-swift"),
                .product(name: "SwiftUIIntrospect", package: "SwiftUI-Introspect"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "Sentry", package: "sentry-cocoa")
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
