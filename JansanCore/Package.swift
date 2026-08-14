// swift-tools-version: 6.0
import PackageDescription

// 雀算の計算ロジック本体。UI(SwiftUI)からも将来のWatch版からも使えるよう、
// UIKit/SwiftUIに依存しない純粋な値型だけで組む。
let package = Package(
    name: "JansanCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JansanCore", targets: ["JansanCore"])
    ],
    targets: [
        .target(name: "JansanCore"),
        .testTarget(name: "JansanCoreTests", dependencies: ["JansanCore"])
    ]
)
