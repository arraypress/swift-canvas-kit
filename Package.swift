// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CanvasKit",
    // Platform floor set by swift-video-grade (macOS 26 / iOS 26).
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        // The shared canvas engine — model, text, renderer, exporters,
        // audio. Headless: no UI frameworks, no network, no AI. The kits
        // that sit on it (ScreenshotKit, SlideKit) own their templates and
        // their CLIs; this owns the drawing.
        .library(
            name: "CanvasKit",
            targets: ["CanvasKit"]
        ),
    ],
    dependencies: [
        // Color grading for image/video plates. Re-exported by CanvasKit,
        // so consumers write one import and the color layer stays its own
        // sharp, standalone-valuable tool underneath.
        .package(url: "https://github.com/arraypress/swift-video-grade.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "CanvasKit",
            dependencies: [.product(name: "VideoGrade", package: "swift-video-grade")],
            resources: [
                .copy("Resources/gradients.json"),
                // The platform-chrome zones the audit checks text against.
                .copy("Resources/safe-zones.json")
            ]
        ),
        .testTarget(
            name: "CanvasKitTests",
            dependencies: ["CanvasKit"]
        ),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
