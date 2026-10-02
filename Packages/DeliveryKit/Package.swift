// swift-tools-version: 6.2
import PackageDescription

// La Consegna (spec 24, ADR 0008): formato .bubo, cifratura HPKE a pezzi, codice di verifica. Codice puro.
let package = Package(
    name: "DeliveryKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DeliveryKit", targets: ["DeliveryKit"]),
    ],
    targets: [
        .target(name: "DeliveryKit"),
        .testTarget(name: "DeliveryKitTests", dependencies: ["DeliveryKit"]),
    ]
)
