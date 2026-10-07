// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "approve-hub-mac",
  platforms: [.macOS(.v26)],
  targets: [
    .executableTarget(name: "ApproveHub"),
    .testTarget(name: "ApproveHubTests", dependencies: ["ApproveHub"]),
  ]
)
