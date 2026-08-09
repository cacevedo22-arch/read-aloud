// swift-tools-version: 5.9
import PackageDescription

// The binary target's name must match the .xcframework inside the zip, which is
// "sherpa-onnx.xcframework". The Swift module it exposes is SherpaOnnxC, from
// the modulemap in SherpaOnnxC.framework.
// Capacitor derives these names from the npm package name ("sherpa-tts"), and
// generates a dependency on product "SherpaTts" in package "SherpaTts". Both
// must match exactly or dependency resolution fails.
let package = Package(
    name: "SherpaTts",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "SherpaTts",
            targets: ["SherpaTts"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .binaryTarget(
            name: "sherpa-onnx",
            url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.4-ios-static.xcframework.zip",
            checksum: "b48ec217952a5b82242ce7d8323fcbc8de54ff900a72df1f0b20bfcf7b08881d"
        ),
        .target(
            name: "SherpaTts",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                "sherpa-onnx"
            ],
            path: "Sources/SherpaTtsPlugin")
    ]
)
