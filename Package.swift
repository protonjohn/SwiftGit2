// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftGit2",
    platforms: [.macOS(.v11)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SwiftGit2",
            targets: ["SwiftGit2"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftGit2",
            dependencies: ["Clibgit2"]
        ),
        .systemLibrary(
            name: "Clibgit2",
            pkgConfig: "libgit2",
            providers: [
                .brewItem(["libgit2"]),
                .aptItem(["libgit2-dev"])
            ]
        ),
        .testTarget(
            name: "SwiftGit2Tests",
            dependencies: [
                "SwiftGit2",
            ]
        )
    ]
)
