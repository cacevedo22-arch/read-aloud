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
        // Dynamic: as a static lib the linker dead-strips SherpaTtsPlugin,
        // because nothing references it directly - Capacitor only finds plugins
        // by scanning the ObjC runtime, so the class must actually be loaded.
        .library(
            name: "SherpaTts",
            type: .dynamic,
            targets: ["SherpaTts"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        // The plain "ios-static" build omits onnxruntime and fails to link with
        // undefined _OrtGetApiBase. This variant has onnxruntime baked in.
        .binaryTarget(
            name: "sherpa-onnx",
            url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.4-ios-shared-onnxruntime-static.xcframework.zip",
            checksum: "889dccd77d3572aebc0b53569b7d9b324314f548d4172eed7759f2b35671d10a"
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
