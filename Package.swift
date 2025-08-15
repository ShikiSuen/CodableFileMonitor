// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "CodableFileMonitor",
  platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10), .tvOS(.v17), .visionOS(.v1)],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "CodableFileMonitor",
      targets: ["CodableFileMonitor"]
    )
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "CodableFileMonitor"
    ),
    .testTarget(
      name: "CodableFileMonitorTests",
      dependencies: ["CodableFileMonitor"]
    ),
  ]
)
