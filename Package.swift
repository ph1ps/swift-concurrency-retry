// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "swift-concurrency-retry",
  platforms: [.iOS(.v16), .macOS(.v13), .macCatalyst(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
  products: [
    .library(name: "Retry", targets: ["Retry"]),
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
      dependencies: ["Retry"]
    )
  ]
)
