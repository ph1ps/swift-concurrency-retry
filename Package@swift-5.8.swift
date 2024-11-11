// swift-tools-version: 5.8

import PackageDescription

let package = Package(
  name: "swift-concurrency-retry",
  platforms: [.iOS(.v16), .macOS(.v13), .macCatalyst(.v16), .tvOS(.v16), .watchOS(.v9)],
  products: [
    .library(name: "Retry", targets: ["Retry"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0")
  ],
  targets: [
    .target(
      name: "_PowShims"
    ),
    .target(
      name: "Retry",
      dependencies: ["_PowShims"]
    ),
    .testTarget(
      name: "RetryTests",
      dependencies: [
        "Retry",
        .product(name: "Clocks", package: "swift-clocks")
      ]
    )
  ]
)
