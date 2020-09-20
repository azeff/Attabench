// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Attabench",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "BenchmarkModel", targets: ["BenchmarkModel"]),
        .library(name: "BenchmarkRunner", targets: ["BenchmarkRunner"]),
        .library(name: "BenchmarkCharts", targets: ["BenchmarkCharts"]),
        .executable(name: "attachart", targets: ["attachart"]),
    ],
    dependencies: [
        .package(url: "https://github.com/azeff/Benchmarking", .branch("master")),
        .package(url: "https://github.com/attaswift/BigInt", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.1"),
    ],
    targets: [
        .target(name: "BenchmarkModel", dependencies: ["BigInt"], path: "BenchmarkModel"),
        .target(name: "BenchmarkRunner", dependencies: ["Benchmarking", "BenchmarkModel"], path: "BenchmarkRunner"),
        .target(name: "BenchmarkCharts", dependencies: ["BenchmarkModel"], path: "BenchmarkCharts"),
        .target(
            name: "attachart",
            dependencies: [
                "BenchmarkModel",
                "BenchmarkCharts",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "attachart"),
    ],
    swiftLanguageVersions: [.v5]
)
