// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "MiKiduCore", targets: ["MiKiduCore"]),
    .executable(name: "mi-kidu-service", targets: ["MiKiduServiceCLI"])
]
var targets: [Target] = [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
    .target(name: "MiKiduCore", dependencies: ["CSQLite"]),
    .executableTarget(name: "MiKiduServiceCLI", dependencies: ["MiKiduCore"]),
    .testTarget(name: "MiKiduCoreTests", dependencies: ["MiKiduCore", "CSQLite"])
]
// Los clientes Apple se compilan en macOS. Linux solo construye el operador y su núcleo compartido.
#if os(macOS)
products += [
    .library(name: "MiKiduShell", targets: ["MiKiduShell"]),
    .library(name: "MiKiduWindowMotion", targets: ["MiKiduWindowMotion"]),
    .library(name: "MiKiduWidgetWatch", targets: ["MiKiduWidgetWatch"]),
    .library(name: "MiKiduPresentation", targets: ["MiKiduPresentation"])
]
targets += [
    .target(name: "MiKiduWindowMotion"),
    .target(name: "MiKiduShell", dependencies: ["MiKiduWindowMotion"]),
    .target(name: "MiKiduWidgetWatch"),
    .target(name: "MiKiduPresentation", dependencies: ["MiKiduCore"]),
    .testTarget(name: "MiKiduPresentationTests", dependencies: ["MiKiduPresentation", "MiKiduCore"])
]
#endif
let package = Package(name: "MiKidu", platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11)], products: products, targets: targets)
