// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ManterAtivo",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ManterAtivo", targets: ["ManterAtivo"]),
        .executable(name: "ManterAtivoProbe", targets: ["ManterAtivoProbe"]),
    ],
    targets: [
        .target(name: "ManterAtivoCore"),
        .executableTarget(
            name: "ManterAtivo",
            dependencies: ["ManterAtivoCore"]
        ),
        .executableTarget(
            name: "ManterAtivoProbe",
            dependencies: ["ManterAtivoCore"]
        ),
        .testTarget(
            name: "ManterAtivoCoreTests",
            dependencies: ["ManterAtivoCore"]
        ),
    ]
)
