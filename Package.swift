// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "approve-hub-mac",
  targets: [
    .executableTarget(name: "ApproveHub"),
    .testTarget(name: "ApproveHubTests", dependencies: ["ApproveHub"]),
  ]
)
