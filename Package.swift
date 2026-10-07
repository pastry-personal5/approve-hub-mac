// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "approve-hub-mac",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "approve-hub", targets: ["ApproveHub"]),
    .executable(name: "approve-hub-service", targets: ["ApproveHubService"]),
    .library(name: "ApproveHubContract", targets: ["ApproveHubContract"]),
    .library(name: "ApproveHubCore", targets: ["ApproveHubCore"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/hummingbird-project/hummingbird.git",
      exact: "2.27.0"
    ),
    .package(
      url: "https://github.com/apple/swift-openapi-generator.git",
      exact: "1.14.0"
    ),
    .package(
      url: "https://github.com/apple/swift-openapi-runtime.git",
      exact: "1.13.0"
    ),
    .package(
      url: "https://github.com/apple/swift-openapi-urlsession.git",
      exact: "1.3.2"
    ),
    .package(
      url: "https://github.com/hummingbird-project/swift-openapi-hummingbird.git",
      exact: "2.1.0"
    ),
  ],
  targets: [
    .target(
      name: "ApproveHubContract",
      dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
      ],
      plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
    ),
    .target(name: "ApproveHubCore", dependencies: ["ApproveHubContract"]),
    .executableTarget(
      name: "ApproveHubService",
      dependencies: [
        "ApproveHubContract",
        "ApproveHubCore",
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
      ],
      plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
    ),
    .executableTarget(
      name: "ApproveHub",
      dependencies: [
        "ApproveHubContract",
        "ApproveHubCore",
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
      ],
      plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
    ),
    .testTarget(name: "ApproveHubCoreTests", dependencies: ["ApproveHubCore"]),
    .testTarget(
      name: "ApproveHubContractTests",
      dependencies: [
        "ApproveHubContract",
        "ApproveHub",
        "ApproveHubService",
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
      ]
    ),
  ]
)
