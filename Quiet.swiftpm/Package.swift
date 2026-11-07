// swift-tools-version: 5.9

// Open this folder (Quiet.swiftpm) in Swift Playgrounds on iPad, or in Xcode on a Mac.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Quiet",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Quiet",
            targets: ["AppModule"],
            bundleIdentifier: "com.quietapp.quiet",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .leaf),
            accentColor: .presetColor(.indigo),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
