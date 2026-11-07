// swift-tools-version: 5.9

// Open this folder (LockIn.swiftpm) in Swift Playgrounds on iPad, or in Xcode on a Mac.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Lock In",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Lock In",
            targets: ["AppModule"],
            bundleIdentifier: "com.quietapp.lockin",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .leaf),
            accentColor: .presetColor(.orange),
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
