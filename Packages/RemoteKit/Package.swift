// swift-tools-version: 6.2
import PackageDescription

// Il Telecomando (spec 21): tipi, cifratura e firma condivisi da Bubo sul Mac e dall'app iPhone.
let package = Package(
    name: "RemoteKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "RemoteKit", targets: ["RemoteKit"]),
    ],
    targets: [
        .target(name: "RemoteKit"),
        .testTarget(name: "RemoteKitTests", dependencies: ["RemoteKit"]),
    ]
)
