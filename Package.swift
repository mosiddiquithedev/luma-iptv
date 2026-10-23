// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Luma", platforms: [.macOS(.v14)],
    products: [.executable(name: "Luma", targets: ["Luma"])],
    targets: [
        .target(name: "LumaCore"),
        .target(name: "CVLC", linkerSettings: [.linkedLibrary("dl")]),
        .executableTarget(name: "Luma", dependencies: ["LumaCore", "CVLC"], linkerSettings: [.linkedFramework("SwiftUI"), .linkedFramework("AVKit"), .linkedFramework("Security")]),
        .executableTarget(name: "LumaChecks", dependencies: ["LumaCore"], path: "Tests/LumaCoreTests")
    ], swiftLanguageModes: [.v5]
)
