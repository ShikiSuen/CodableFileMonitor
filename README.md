# CodableFileMonitor<T: Codable, Encoder, Decoder>

A Swift 6.0+ generic file monitor that automatically manages Codable data and broadcasts changes using the Swift Observation framework.

## Overview

CodableFileMonitor is a modern, type-safe file monitoring solution that:

- **Generic Support**: Works with any `Codable` type using `CodableFileMonitor<T: Codable, Encoder: CFMDataEncoder, Decoder: CFMDataDecoder>`
- **Swift 6.0+ Compatible**: Built for Swift 6.0+ with strict concurrency checking and `@unchecked Sendable`
- **Multi-Platform**: Supports macOS 14+, iOS 17+, watchOS 10+, tvOS 17+, visionOS 1+
- **Swift Observation Integration**: Uses `@Observable` macro for automatic property change broadcasting
- **File System Monitoring**: Automatically detects and syncs external file changes using polling (500ms intervals)
- **Thread-Safe**: Implements proper Swift 6 concurrency patterns with NSLock for safe concurrent access
- **Custom Codec Support**: Works with any encoder/decoder conforming to `CFMDataEncoder`/`CFMDataDecoder` protocols

## Key Features

### 🔧 Generic Type Support
```swift
// Works with any Codable type and custom codecs
let configMonitor = JSONCodableFileMonitor(
    fileURL: configURL,
    defaultValue: AppConfig.default
)

// Convenience initializer for JSON (most common usage)
let jsonConfigMonitor = CodableFileMonitor(
    fileURL: configURL,
    defaultValue: AppConfig.default
)

// Using PropertyList codecs
let plistMonitor = PlistCodableFileMonitor<AppConfig>(
    fileURL: documentsDirectory.appendingPathComponent("config.plist"),
    defaultValue: .default
)

// Using type aliases for common patterns
let jsonMonitor: JSONCodableFileMonitor<AppConfig> = CodableFileMonitor(
    fileURL: configURL,
    defaultValue: AppConfig.default
)

let plistMonitor2: PlistCodableFileMonitor<AppConfig> = CodableFileMonitor(
    fileURL: plistURL,
    defaultValue: AppConfig.default,
    encoder: PropertyListEncoder(),
    decoder: PropertyListDecoder()
)
```

### 📡 Swift Observation Framework
```swift
import SwiftUI

struct ConfigView: View {
    @State private var appState: AppState

    init(configURL: URL) {
        self._appState = State(initialValue: AppState(configURL: configURL))
    }
    
    var body: some View {
        VStack {
            // Automatically updates when monitor.data changes
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
    }
}
```

### 🔄 Automatic Synchronization
```swift
// Data changes automatically trigger file saves
monitor.data = newConfiguration // Saves to file asynchronously

// External file changes automatically update in-memory data
// File modified by external process → monitor.data updates automatically
```

### ⚡ Modern async/await API
```swift
// Start monitoring with async/await
try await monitor.startMonitoring()

// Manual operations
try await monitor.reloadData()
await monitor.saveData()
await monitor.stopMonitoring()
```

## Usage Example

```swift
import Foundation
import CodableFileMonitor

// Define your Codable data structure
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
    .appendingPathComponent("app_config.json")
let jsonMonitor = JSONCodableFileMonitor(
    fileURL: configURL,
    defaultValue: AppConfig.default
)

// Start monitoring
try await jsonMonitor.startMonitoring()

// Access and modify data (automatically saves)
print("Current app name: \(jsonMonitor.data.appName)")

let updatedConfig = AppConfig(
    appName: "UpdatedApp",
    version: "2.0.0",
    debugEnabled: true,
    maxConnections: 200,
    features: ["feature1", "feature2", "newFeature"]
)
jsonMonitor.data = updatedConfig

// The file is automatically saved and changes are observable
```

## Architecture

### Thread Safety
- Uses custom `DataStorage` class with `NSLock` for thread-safe property access
- Implements `@unchecked Sendable` with proper synchronization using `CheckedContinuation`
- Compatible with Swift 6 strict concurrency checking

### File Monitoring
- Polls file system every 500ms for changes using a background `Task`
- Compares modification timestamps to avoid unnecessary reloads
- Handles file creation, modification, and deletion gracefully
- Automatically creates parent directories when saving files

### Error Handling
```swift
enum CodableFileMonitorError: LocalizedError {
    case fileNotFound
    case invalidData
    case encodingFailed(Error)
    case decodingFailed(Error)
    case fileSystemError(Error)
}
```

### Performance
- Lazy loading: Only reads file when changes are detected via timestamp comparison
- Atomic writes: Uses `Data.WritingOptions.atomic` to prevent corruption during saves
- Efficient polling: Minimal CPU usage with smart timestamp checking
- Background task management: Proper cleanup and cancellation support

## API Reference

### Initialization
```swift
// Generic initializer with custom codecs
public init<T: Codable, E: CFMDataEncoder, D: CFMDataDecoder>(
    fileURL: URL, 
    defaultValue: T,
    encoder: E,
    decoder: D
)

// Convenience initializer using JSON codecs
public convenience init(fileURL: URL, defaultValue: T) 
    where Encoder == JSONEncoder, Decoder == JSONDecoder
```

### Properties
```swift
public var data: T                              // Observable data
public let fileURL: URL                         // File being monitored
public let defaultValue: T                      // Fallback value
public var isMonitoring: Bool { get }           // Monitoring status
public var lastModificationDate: Date? { get }  // Last file modification
```

### Methods
```swift
public func startMonitoring() async throws      // Start file monitoring
public func stopMonitoring() async             // Stop file monitoring
public func reloadData() async throws          // Manual reload from file
public func saveData() async                   // Manual save to file
```

## Requirements

- **Swift**: 6.0+
- **Platforms**: 
  - macOS 14+
  - iOS 17+ 
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+
- **Frameworks**: Foundation, Observation

## Integration with SwiftUI

The `@Observable` macro makes CodableFileMonitor perfect for SwiftUI:

```swift
@Observable
class AppState {
    var configMonitor: JSONCodableFileMonitor<AppConfig>

    init(configURL: URL) {
        self.configMonitor = JSONCodableFileMonitor(fileURL: configURL, defaultValue: .default)
    }

    var debugEnabled: Bool {
        get { configMonitor.data.debugEnabled }
        set { configMonitor.data.debugEnabled = newValue }
    }
}
```

## Custom Codecs Support

CodableFileMonitor supports any encoder/decoder that conforms to the `CFMDataEncoder`/`CFMDataDecoder` protocols:

```swift
import Foundation
import CodableFileMonitor

// Protocol definitions (built into the library)
public protocol CFMDataEncoder {
    func encodeToData<T: Encodable>(_ value: T) throws -> Data
}

public protocol CFMDataDecoder {
    func decodeFromData<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

// Using PropertyList codecs
let plistEncoder = PropertyListEncoder()
plistEncoder.outputFormat = .xml
let plistDecoder = PropertyListDecoder()

let monitor = CodableFileMonitor(
    fileURL: plistURL,
    defaultValue: AppConfig.default,
    encoder: PropertyListEncoder(),
    decoder: PropertyListDecoder()
)

// For JSON (default behavior), use the convenience initializer:
let jsonMonitor = JSONCodableFileMonitor<AppConfig>(
    fileURL: documentsDirectory.appendingPathComponent("config.json"),
    defaultValue: .default
)

// Type aliases available for common usage patterns:
let jsonMonitor2: JSONCodableFileMonitor<AppConfig> = CodableFileMonitor(
    fileURL: configURL,
    defaultValue: AppConfig.default
)

let plistMonitor3 = PlistCodableFileMonitor<AppConfig>(
    fileURL: documentsDirectory.appendingPathComponent("config3.plist"),
    defaultValue: .default
)
```

### Built-in Codec Support

The library automatically extends Foundation's built-in codecs:

- `JSONEncoder` / `JSONDecoder` → `CFMDataEncoder` / `CFMDataDecoder`
- `PropertyListEncoder` / `PropertyListDecoder` → `CFMDataEncoder` / `CFMDataDecoder`

### Custom Codec Implementation

You can create your own codecs by conforming to the protocols:

```swift
struct CustomEncoder: CFMDataEncoder {
    func encodeToData<T: Encodable>(_ value: T) throws -> Data {
        // Your custom encoding logic
    }
}

struct CustomDecoder: CFMDataDecoder {
    func decodeFromData<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Your custom decoding logic
    }
}
```

## Observation Behavior

### Property-Level Observation

The `data` property is fully observable, but nested property changes require setting the entire `data` property:

```swift
// ✅ This triggers observation and auto-save:
var config = monitor.data
config.appName = "New Name"
monitor.data = config

// ❌ This won't work for struct-based Codable types (compilation error):
// monitor.data.appName = "New Name"  

// ✅ For SwiftUI bindings, use this pattern:
Toggle("Debug Mode", isOn: Binding(
    get: { appState.configMonitor.data.debugEnabled },
    set: { newValue in
        var config = appState.configMonitor.data
        config.debugEnabled = newValue
        appState.configMonitor.data = config
    }
))

// See the comprehensive SwiftUI example in the "Swift Observation Framework" section for complete implementation.
```

### SwiftUI Integration

All properties under `monitor.data` automatically trigger SwiftUI view updates when the parent `data` property changes. See the comprehensive SwiftUI example in the "Swift Observation Framework" section above for implementation details.

## Type Aliases

For convenience, the library provides type aliases for common usage patterns:

```swift
// Most common usage - JSON with any Codable type
public typealias JSONCodableFileMonitor<T: Codable> = 
    CodableFileMonitor<T, JSONEncoder, JSONDecoder>

// PropertyList usage
public typealias PlistCodableFileMonitor<T: Codable> = 
    CodableFileMonitor<T, PropertyListEncoder, PropertyListDecoder>

// Usage examples:
let jsonConfig: JSONCodableFileMonitor<AppConfig> = CodableFileMonitor(
    fileURL: configURL,
    defaultValue: .default
)

let plistConfig: PlistCodableFileMonitor<AppConfig> = CodableFileMonitor(
    fileURL: documentsDirectory.appendingPathComponent("config.plist"),
    defaultValue: .default,
    encoder: PropertyListEncoder(),
    decoder: PropertyListDecoder()
)
```

## Demo

The included `CodableFileMonitorDemo.swift` file contains comprehensive usage examples and integration patterns, demonstrating how to use `CodableFileMonitor` for:

- JSON and PropertyList configuration management
- SwiftUI integration with `@Observable`
- Error handling and robust file operations
- Managing multiple configuration files simultaneously

**Note**: Since Swift scripts don't support local Swift Package imports, the demo file serves as documentation and reference implementation rather than an executable script. To run the examples in your own project, add CodableFileMonitor as a dependency to your `Package.swift` and copy the relevant code examples from `CodableFileMonitorDemo.swift`, adapting them to your specific use case.
