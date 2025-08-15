// CodableFileMonitor Demo - Usage Examples and Integration Patterns
// ====================
// This file demonstrates how to integrate CodableFileMonitor into your Swift projects.
// Since Swift scripts don't support local Swift Package imports, this serves as
// documentation and reference implementation.

// (c) 2025 and onwards Shiki Suen (MIT License).
// This code is released under the SPDX-License-Identifier: `MIT`.

import Foundation

// MARK: - Usage Examples

/*
 To use CodableFileMonitor in your project, add it as a dependency in Package.swift:

 dependencies: [
     .package(url: "https://github.com/ShikiSuen/CodableFileMonitor.git", from: "1.0.0")
 ],
 targets: [
     .target(name: "YourTarget", dependencies: ["CodableFileMonitor"])
 ]

 Then import it in your Swift files:
 import CodableFileMonitor
*/

// MARK: - Example 1: Basic JSON Configuration Management

/*
// Define your configuration structure
struct AppConfig: Codable, Equatable {
    let appName: String
    let version: String
    let debugEnabled: Bool
    let maxConnections: Int
    let features: [String]

    static let `default` = AppConfig(
        appName: "MyApp",
        version: "1.0.0",
        debugEnabled: false,
        maxConnections: 100,
        features: ["feature1", "feature2"]
    )
}

// Initialize the monitor (uses JSON codecs by default)
let configURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    .appendingPathComponent("config.json")

let monitor = JSONCodableFileMonitor(
    fileURL: configURL,
    defaultValue: AppConfig.default
)

// Usage in async context
func setupConfiguration() async throws {
    // Start monitoring
    try await monitor.startMonitoring()
    print("✓ Monitoring started: \(monitor.isMonitoring)")

    // Modify data (automatically saves to file)
    let updatedConfig = AppConfig(
        appName: "MyAwesomeApp",
        version: "2.0.0",
        debugEnabled: true,
        maxConnections: 200,
        features: ["feature1", "feature2", "newFeature"]
    )
    monitor.data = updatedConfig

    // Wait for save operation
    try await Task.sleep(nanoseconds: 100_000_000)
    print("✓ Data updated and saved automatically")

    // Manual operations
    try await monitor.reloadData()  // Reload from file
    await monitor.saveData()        // Force save

    // Cleanup
    await monitor.stopMonitoring()
}
*/

// MARK: - Example 2: Custom PropertyList Codecs

/*
// Using PropertyList format instead of JSON
let plistURL = documentsDirectory.appendingPathComponent("config.plist")

let encoder = PropertyListEncoder()
encoder.outputFormat = .xml
let decoder = PropertyListDecoder()

let plistMonitor = CodableFileMonitor(
    fileURL: plistURL,
    defaultValue: AppConfig.default,
    encoder: encoder,
    decoder: decoder
)

// Or using the type alias for convenience
let plistMonitor2: PlistCodableFileMonitor<AppConfig> = CodableFileMonitor(
    fileURL: plistURL,
    defaultValue: AppConfig.default,
    encoder: PropertyListEncoder(),
    decoder: PropertyListDecoder()
)
*/

// MARK: - Example 3: SwiftUI Integration

/*
import SwiftUI

@Observable
class AppState {
    let configMonitor: JSONCodableFileMonitor<AppConfig>

    init(configURL: URL) {
        self.configMonitor = CodableFileMonitor(
            fileURL: configURL,
            defaultValue: AppConfig.default
        )

        // Start monitoring in a background task
        Task {
            try await configMonitor.startMonitoring()
        }
    }

    // Convenience computed properties
    var appName: String {
        get { configMonitor.data.appName }
        set {
            var config = configMonitor.data
            config.appName = newValue
            configMonitor.data = config  // Triggers auto-save
        }
    }

    var debugEnabled: Bool {
        get { configMonitor.data.debugEnabled }
        set {
            var config = configMonitor.data
            config.debugEnabled = newValue
            configMonitor.data = config
        }
    }
}

struct ConfigView: View {
    @State private var appState: AppState

    init(configURL: URL) {
        self._appState = State(initialValue: AppState(configURL: configURL))
    }

    var body: some View {
        VStack(spacing: 16) {
            // These automatically update when monitor.data changes
            Text("App: \(appState.configMonitor.data.appName)")
                .font(.headline)

            Text("Version: \(appState.configMonitor.data.version)")

            Text("Connections: \(appState.configMonitor.data.maxConnections)")

            Text("Features: \(appState.configMonitor.data.features.joined(separator: ", "))")

            Toggle("Debug Mode", isOn: Binding(
                get: { appState.configMonitor.data.debugEnabled },
                set: { newValue in
                    var config = appState.configMonitor.data
                    config.debugEnabled = newValue
                    appState.configMonitor.data = config
                }
            ))

            Button("Save Configuration") {
                Task {
                    await appState.configMonitor.saveData()
                }
            }

            Text("Last modified: \(appState.configMonitor.lastModificationDate?.formatted() ?? "Never")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
*/

// MARK: - Example 4: Advanced Usage with Error Handling

/*
class ConfigurationManager {
    private let monitor: JSONCodableFileMonitor<AppConfig>

    init(fileURL: URL) {
        self.monitor = JSONCodableFileMonitor(
            fileURL: fileURL,
            defaultValue: AppConfig.default
        )
    }

    func start() async throws {
        do {
            try await monitor.startMonitoring()
            print("Configuration monitoring started")
        } catch {
            print("Failed to start monitoring: \(error)")
            throw error
        }
    }

    func updateConfiguration(_ newConfig: AppConfig) async {
        monitor.data = newConfig

        // Wait for save to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        print("Configuration updated: \(newConfig.appName)")
    }

    func reloadFromDisk() async throws {
        try await monitor.reloadData()
        print("Configuration reloaded from disk")
    }

    var currentConfig: AppConfig {
        monitor.data
    }

    var isMonitoring: Bool {
        monitor.isMonitoring
    }

    func stop() async {
        await monitor.stopMonitoring()
        print("Configuration monitoring stopped")
    }
}

// Usage
func useConfigurationManager() async throws {
    let configURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("app-config.json")

    let manager = ConfigurationManager(fileURL: configURL)

    try await manager.start()

    // Update configuration
    let newConfig = AppConfig(
        appName: "Advanced App",
        version: "3.0.0",
        debugEnabled: true,
        maxConnections: 500,
        features: ["advanced-feature", "monitoring", "auto-save"]
    )

    await manager.updateConfiguration(newConfig)

    // Later...
    await manager.stop()
}
*/

// MARK: - Example 5: Multiple Configuration Files

/*
class MultiConfigManager {
    let appConfig: JSONCodableFileMonitor<AppConfig>
    let userSettings: PlistCodableFileMonitor<UserSettings>

    struct UserSettings: Codable, Equatable {
        let theme: String
        let notifications: Bool
        let autoSave: Bool

        static let `default` = UserSettings(
            theme: "system",
            notifications: true,
            autoSave: true
        )
    }

    init(configDirectory: URL) {
        self.appConfig = JSONCodableFileMonitor(
            fileURL: configDirectory.appendingPathComponent("app.json"),
            defaultValue: AppConfig.default
        )

        self.userSettings = CodableFileMonitor(
            fileURL: configDirectory.appendingPathComponent("user.plist"),
            defaultValue: UserSettings.default,
            encoder: PropertyListEncoder(),
            decoder: PropertyListDecoder()
        )
    }

    func startAll() async throws {
        try await appConfig.startMonitoring()
        try await userSettings.startMonitoring()
        print("All configuration monitors started")
    }

    func stopAll() async {
        await appConfig.stopMonitoring()
        await userSettings.stopMonitoring()
        print("All configuration monitors stopped")
    }
}
*/

// MARK: - Key Features Demonstrated

/*
 📋 Key Features of CodableFileMonitor:

 ✅ Generic type support: CodableFileMonitor<T: Codable, Encoder, Decoder>
 ✅ Swift 6.0+ concurrency with async/await and @unchecked Sendable
 ✅ Automatic file persistence on data changes
 ✅ External file change detection and auto-reload (500ms polling)
 ✅ Thread-safe concurrent access using NSLock
 ✅ Swift Observation framework integration (@Observable)
 ✅ Manual save/reload operations
 ✅ Proper error handling and cleanup
 ✅ Custom codec support (JSON, PropertyList, etc.)
 ✅ Type aliases for common usage patterns
 ✅ SwiftUI integration with automatic UI updates
 ✅ Multi-platform support (macOS, iOS, watchOS, tvOS, visionOS)
 ✅ Atomic file writes to prevent corruption
 ✅ Smart timestamp-based change detection
 ✅ Background task management with proper cleanup
*/

// MARK: - Integration Instructions

/*
 🚀 How to integrate into your project:

 1. Add to Package.swift dependencies:
    .package(url: "https://github.com/ShikiSuen/CodableFileMonitor.git", from: "1.0.0")

 2. Add to target dependencies:
    .target(name: "YourTarget", dependencies: ["CodableFileMonitor"])

 3. Import in your Swift files:
    import CodableFileMonitor

 4. Define your Codable data structures

 5. Initialize monitors with file URLs and default values

 6. Start monitoring with try await monitor.startMonitoring()

 7. Access/modify data via monitor.data (auto-saves)

 8. Stop monitoring when done with await monitor.stopMonitoring()
*/

print("📚 CodableFileMonitor Demo - See source code for comprehensive usage examples")
print("🔗 GitHub: https://github.com/ShikiSuen/CodableFileMonitor")
print("📖 This file contains detailed integration examples and patterns")

print("� CodableFileMonitor Demo - See source code for comprehensive usage examples")
print("🔗 GitHub: https://github.com/ShikiSuen/CodableFileMonitor")
print("📖 This file contains detailed integration examples and patterns")
