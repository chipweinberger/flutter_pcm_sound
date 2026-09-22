// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_pcm_sound",
    platforms: [
        .macOS("10.14"),
    ],
    products: [
        .library(name: "flutter-pcm-sound", targets: ["flutter_pcm_sound"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_pcm_sound",
            dependencies: [],
            cSettings: [
                .headerSearchPath("include/flutter_pcm_sound"),
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
            ]
        )
    ]
)
