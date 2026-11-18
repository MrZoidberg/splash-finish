// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SplashFinish",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SplashFinish", targets: ["SplashFinish"])],
    dependencies: [
        .package(path: "Vendor/BobukKit"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "SplashFinishCore"),
        .executableTarget(name: "SplashFinish", dependencies: ["SplashFinishCore", .product(name: "Sparkle", package: "Sparkle"),
                                                                    .product(name: "BobukUI", package: "BobukKit")],
                          resources: [.copy("Resources/Integrations"), .copy("Resources/Orca")]),
        .testTarget(name: "SplashFinishCoreTests", dependencies: ["SplashFinishCore"]),
        .testTarget(name: "SplashFinishTests", dependencies: ["SplashFinish", .product(name: "BobukUI", package: "BobukKit")])
    ]
)
