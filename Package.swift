// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "aishow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AishowCore", targets: ["AishowCore"]),
        .executable(name: "aishow", targets: ["aishow"]),
    ],
    targets: [
        // 純粋ロジック(サイト特定 → workflow 選択、コンテキストパック、呪文選択)。OS 依存なし・テスト対象。
        .target(name: "AishowCore", path: "Sources/AishowCore"),
        // CLI。Step 2〜5 でサブコマンドを増やし、Step 6 でメニューバー常駐アプリに昇格する。
        .executableTarget(name: "aishow", dependencies: ["AishowCore"], path: "Sources/aishow"),
        .testTarget(name: "AishowCoreTests", dependencies: ["AishowCore"], path: "Tests/AishowCoreTests"),
    ]
)
