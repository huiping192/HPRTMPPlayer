// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HPRTMPPlayer",
    platforms: [.iOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "HPRTMPPlayer",
            targets: ["HPRTMPPlayer"]),
    ], dependencies: [
        .package(path: "../HPRTMP")
      //.package(url: "https://github.com/huiping192/HPRTMP", from: "0.0.2")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "HPRTMPPlayer",
            dependencies: [
          .product(name: "HPRTMP", package: "HPRTMP")
        ],
        linkerSettings: [
          .linkedFramework("VideoToolbox"),
          .linkedFramework("AudioToolbox"),
          .linkedFramework("AVFoundation"),
          .linkedFramework("Foundation"),
          .linkedFramework("UIKit"),
        ]),
        .testTarget(
            name: "HPRTMPPlayerTests",
            dependencies: ["HPRTMPPlayer"]),
    ]
)
