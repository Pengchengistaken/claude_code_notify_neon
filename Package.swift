// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NeonNotify",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NeonNotify", targets: ["NeonNotify"]),
        .executable(name: "neon-hook", targets: ["neon-hook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/ColorfulX.git", from: "5.8.0"),
        .package(url: "https://github.com/simibac/ConfettiSwiftUI.git", from: "2.0.0"),
        .package(url: "https://github.com/orchetect/SettingsAccess.git", from: "2.1.0"),
    ],
    targets: [
        // app 与 hook 共用的数据契约（状态枚举、状态文件读写路径）
        .target(name: "NeonCore", path: "Sources/NeonCore"),
        .executableTarget(
            name: "NeonNotify",
            dependencies: [
                "NeonCore",
                .product(name: "ColorfulX", package: "ColorfulX"),
                .product(name: "ConfettiSwiftUI", package: "ConfettiSwiftUI"),
                .product(name: "SettingsAccess", package: "SettingsAccess"),
            ],
            path: "Sources/NeonNotify"
        ),
        .executableTarget(
            name: "neon-hook",
            dependencies: ["NeonCore"],
            path: "Sources/neon-hook"
        ),
        // 调试工具：逐层拆开灯带渲染管线，不进 app bundle
        .executableTarget(
            name: "strip-probe",
            dependencies: [
                .product(name: "ColorfulX", package: "ColorfulX"),
                .product(name: "ConfettiSwiftUI", package: "ConfettiSwiftUI"),
            ],
            path: "Sources/strip-probe"
        ),
    ]
)
