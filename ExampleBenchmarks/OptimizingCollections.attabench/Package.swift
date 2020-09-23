// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Benchmark",
    products: [
        .executable(name: "Benchmark", targets: ["Benchmark"])
    ],
    dependencies: [
        .package(url: "https://github.com/azeff/Benchmarking", from: "1.0.1")
    ],
    targets: [
        .target(name: "Benchmark", dependencies: ["Benchmarking"], path: "Sources"),
    ],
    swiftLanguageVersions: [.v5]
)
