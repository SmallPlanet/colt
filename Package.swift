// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

/*
When you change the configuration in the Packages.swift files to remove or add more dependencies,
you should re-generate the Xcode project file with "swift package generate-xcodeproj". - Angie
*/

import PackageDescription

let package = Package(
    name: "colt",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.1.0"),
        .package(name: "Progress", url: "https://github.com/jkandzi/Progress.swift", from: "0.4.0"),
        .package(name: "INI", url: "https://github.com/Bouke/INI", from: "1.2.0")
    ],
    targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.        
        .target(
            name: "colt",
            dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser"), "Progress", "INI"]),
        .testTarget(
            name: "ColtTests",
            dependencies: ["colt"])
    ]
)
