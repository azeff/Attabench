// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "Benchmark",
    products: [
        .executable(name: "Benchmark", targets: ["Benchmark"])
    ],
    dependencies: [
    .package(url: "https://github.com/azeff/Benchmarking", .branch("master"))
    ],
    targets: [
        .target(name: "Benchmark", dependencies: ["Benchmarking"], path: "Sources"),
    ],
    swiftLanguageVersions: [.v5]
)
