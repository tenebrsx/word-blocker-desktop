// swift-tools-version:5.9
// Pure-logic package so the engine + self-control logic can be tested anywhere (`swift test`, incl. Linux).
import PackageDescription

let package = Package(
    name: "WordBlockerEngine",
    targets: [
        .target(name: "Engine", path: "App/Engine"),
        .testTarget(name: "EngineTests", dependencies: ["Engine"], path: "Tests",
                    exclude: ["Vectors"]),
    ]
)
