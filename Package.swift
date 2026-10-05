// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NilaiKinerja",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NilaiKinerja",
            path: "Sources/NilaiKinerja"
        )
    ]
)
