// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorkTrackerCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "WorkTrackerCore", targets: ["WorkTrackerCore"])
    ],
    targets: [
        .target(
            name: "WorkTrackerCore",
            path: ".",
            exclude: [
                ".beans",
                ".beans.yml",
                ".git",
                ".gitignore",
                ".build",
                "Tests",
                "WorkTracker/Assets.xcassets",
                "WorkTracker/Models/TrackerViewModel.swift",
                "WorkTracker/Services/AIClient.swift",
                "WorkTracker/Services/LinearClient.swift",
                "WorkTracker/Views",
                "WorkTracker/WorkTrackerApp.swift",
                "WorkTracker.xcodeproj",
                "add_file.rb"
            ],
            sources: [
                "WorkTracker/Models/TrackerModels.swift",
                "WorkTracker/Services/DatabaseManager.swift"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "WorkTrackerCoreTests",
            dependencies: ["WorkTrackerCore"],
            path: "Tests/WorkTrackerCoreTests",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
