// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clattering",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "Clattering",
            path: "Sources/Clattering",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Clattering/Info.plist"])
            ]
        )
    ]
)
