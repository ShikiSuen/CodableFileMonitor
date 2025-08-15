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
let configMonitor = CodableFileMonitor<AppConfig, JSONEncoder, JSONDecoder>(
    fileURL: configFileURL,
    defaultValue: AppConfig.default,
    encoder: JSONEncoder(),
    decoder: JSONDecoder()
)

// Convenience initializer for JSON (most common usage)
let jsonConfigMonitor = CodableFileMonitor(
    fileURL: configFileURL,
    defaultValue: AppConfig.default
)

// Using PropertyList codecs
let plistMonitor = CodableFileMonitor(
    fileURL: plistFileURL,
    defaultValue: UserData.default,
    encoder: PropertyListEncoder(),
    decoder: PropertyListDecoder()
)

// Using type aliases for common patterns
let jsonMonitor: JSONCodableFileMonitor<AppConfig> = CodableFileMonitor(
    fileURL: jsonFileURL,
    defaultValue: AppConfig.default
)

let plistMonitor2: PlistCodableFileMonitor<UserData> = CodableFileMonitor(
    fileURL: plistFileURL,
    defaultValue: UserData.default,
    encoder: PropertyListEncoder(),
    decoder: PropertyListDecoder()
)
```

### 📡 Swift Observation Framework
```swift
import SwiftUI

struct ConfigView: View {
    let monitor: CodableFileMonitor<AppConfig>
    
    var body: some View {
        VStack {
            // Automatically updates when monitor.data changes
            Text("App: \(monitor.data.appName)")
            Text("Version: \(monitor.data.version)")
            Toggle("Debug Mode", isOn: Binding(
                get: { monitor.data.debugEnabled },
                set: { newValue in
                    var config = monitor.data
                    config.debugEnabled = newValue
                    monitor.data = config // Auto-saves to file
                }
            ))
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
let configURL = documentsDirectory.appendingPathComponent("config.json")
let monitor = CodableFileMonitor(
    fileURL: configURL,
    defaultValue: AppConfig.default
)

// Start monitoring
try await monitor.startMonitoring()

// Access and modify data (automatically saves)
print("Current app name: \(monitor.data.appName)")

let updatedConfig = AppConfig(
    appName: "UpdatedApp",
    version: "2.0.0",
    debugEnabled: true,
    maxConnections: 200,
    features: ["feature1", "feature2", "newFeature"]
)
monitor.data = updatedConfig

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
    let configMonitor: CodableFileMonitor<AppConfig>
    
    init(configURL: URL) {
        self.configMonitor = CodableFileMonitor(
            fileURL: configURL,
            defaultValue: AppConfig.default
        )
        Task {
            try await configMonitor.startMonitoring()
        }
    }
    
    var appName: String {
        get { configMonitor.data.appName }
        set {
            var config = configMonitor.data
            config.appName = newValue
            configMonitor.data = config
        }
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
    fileURL: configURL.appendingPathExtension("plist"),
    defaultValue: AppConfig.default,
    encoder: plistEncoder,
    decoder: plistDecoder
)

// For JSON (default behavior), use the convenience initializer:
let jsonMonitor = CodableFileMonitor(
    fileURL: configURL.appendingPathExtension("json"),
    defaultValue: AppConfig.default
)

// Type aliases available for common usage patterns:
let jsonMonitor2: JSONCodableFileMonitor<AppConfig> = CodableFileMonitor(
    fileURL: configURL.appendingPathExtension("json"),
    defaultValue: AppConfig.default
)

let plistMonitor3: PlistCodableFileMonitor<AppConfig> = CodableFileMonitor(
    fileURL: configURL.appendingPathExtension("plist"),
    defaultValue: AppConfig.default,
    encoder: PropertyListEncoder(),
    decoder: PropertyListDecoder()
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
    get: { monitor.data.debugEnabled },
    set: { newValue in
        var config = monitor.data
        config.debugEnabled = newValue
        monitor.data = config  // Triggers observation + auto-save
    }
))
```

### SwiftUI Integration

All properties under `monitor.data` automatically trigger SwiftUI view updates when the parent `data` property changes:

```swift
struct ConfigView: View {
    @State var monitor: CodableFileMonitor<AppConfig, JSONEncoder, JSONDecoder>
    
    var body: some View {
        // These all update automatically when monitor.data changes
        VStack {
            Text("App: \(monitor.data.appName)")
            Text("Version: \(monitor.data.version)")
            Text("Debug: \(monitor.data.debugEnabled ? "ON" : "OFF")")
            Text("Connections: \(monitor.data.maxConnections)")
            Text("Features: \(monitor.data.features.joined(separator: ", "))")
        }
    }
}
```

## Migration from FolderMonitor

The new CodableFileMonitor replaces any previous FolderMonitor with enhanced capabilities:

| Previous Approach | CodableFileMonitor |
|------------------|-------------------|
| Directory monitoring | File-specific monitoring |
| No type safety | Generic `<T: Codable, Encoder, Decoder>` support |
| Manual state management | Automatic data persistence |
| Basic change detection | Smart timestamp-based updates |
| Limited concurrency | Full Swift 6 concurrency support |
| JSON-only | Custom codec support (JSON, PropertyList, etc.) |

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
    fileURL: jsonURL,
    defaultValue: AppConfig.default
)

let plistConfig: PlistCodableFileMonitor<Settings> = CodableFileMonitor(
    fileURL: plistURL, 
    defaultValue: Settings.default,
    encoder: PropertyListEncoder(),
    decoder: PropertyListDecoder()
)
```

## Demo

The included `CodableFileMonitorDemo.swift` file contains comprehensive usage examples and integration patterns:

```swift
// View the demo file for detailed examples:
// - Basic JSON configuration management
// - Custom PropertyList codecs usage  
// - SwiftUI integration patterns
// - Advanced error handling
// - Multiple configuration files management
// - Type aliases usage examples
```

**Note**: Since Swift scripts don't support local Swift Package imports, the demo file serves as documentation and reference implementation rather than an executable script.

To run the examples in your own project:

1. Add CodableFileMonitor as a dependency to your Package.swift
2. Copy the relevant code examples from `CodableFileMonitorDemo.swift`
3. Adapt them to your specific use case

The demo showcases:
- Generic type usage with custom configuration structures
- Automatic file persistence on data changes  
- External file change detection and auto-reload
- Manual save/reload operations
- Concurrency safety with async/await
- Error handling and proper cleanup
- Custom codec support (JSON vs PropertyList)
- Type alias usage examples
- Thread-safe concurrent access patterns
- Swift Observation framework integration
- SwiftUI integration with automatic UI updates
