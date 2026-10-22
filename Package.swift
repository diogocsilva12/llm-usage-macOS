// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "LimitbarCore", targets: ["LimitbarCore"])]
var targets: [Target] = [
    .target(name: "LimitbarCore"),
    .testTarget(name: "LimitbarCoreTests", dependencies: ["LimitbarCore"], resources: [.copy("Fixtures")]),
]

#if os(macOS)
products.append(.executable(name: "Limitbar", targets: ["Limitbar"]))
targets.append(.executableTarget(name: "Limitbar", dependencies: ["LimitbarCore"]))
#endif

let package = Package(
    name: "Limitbar",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
