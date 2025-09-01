// (c) 2025 and onwards Shiki Suen (MIT License).
// ====================
// This code is released under the SPDX-License-Identifier: `MIT`.

/// CodableFileMonitor: A Swift 6.0+ generic file monitor that automatically manages Codable data
/// and broadcasts changes using Swift Observation framework.
///
/// ## Overview
///
/// This library provides a type-safe, thread-safe solution for monitoring and persisting
/// Codable data structures to files with automatic change detection and SwiftUI integration.
///
/// ## Key Features
///
/// - **Generic Type Safety**: Works with any `Codable` type
/// - **Custom Codec Support**: JSON, PropertyList, or custom encoders/decoders
/// - **Automatic Persistence**: Changes trigger automatic file saves
/// - **External Change Detection**: 500ms polling for external file modifications
/// - **Thread Safety**: NSLock-based synchronization for concurrent access
/// - **Swift 6 Concurrency**: Full async/await support with `@unchecked Sendable`
/// - **SwiftUI Integration**: `@Observable` macro for reactive UI updates
/// - **Multi-platform**: macOS 14+, iOS 17+, watchOS 10+, tvOS 17+, visionOS 1+
///
/// ## Basic Usage
///
/// ```swift
/// import CodableFileMonitor
///
/// struct AppConfig: Codable {
///     let name: String
///     let version: String
/// }
///
/// let monitor = CodableFileMonitor(
///     fileURL: configURL,
///     defaultValue: AppConfig(name: "MyApp", version: "1.0")
/// )
///
/// try await monitor.startMonitoring()
/// monitor.data = AppConfig(name: "UpdatedApp", version: "2.0")  // Auto-saves
/// await monitor.stopMonitoring()
/// ```

import Foundation

#if canImport(Observation)
  import Observation
#endif

// MARK: - Protocol Definitions

/// Protocol for encoders that can encode Codable types to Data.
///
/// This protocol allows `CodableFileMonitor` to work with any encoder that can
/// produce `Data` from `Encodable` types. Foundation's `JSONEncoder` and
/// `PropertyListEncoder` conform to this protocol automatically via extensions.
///
/// ## Example
/// ```swift
/// struct CustomEncoder: CFMDataEncoder {
///     func encodeToData<T: Encodable>(_ value: T) throws -> Data {
///         // Your custom encoding logic here
///         return customEncodedData
///     }
/// }
/// ```
public protocol CFMDataEncoder {
  /// Encodes the given top-level value and returns its Data representation.
  ///
  /// - Parameter value: The value to encode.
  /// - Returns: A new `Data` value containing the encoded data.
  /// - Throws: An error if any value throws an error during encoding.
  func encodeToData<T: Encodable>(_ value: T) throws -> Data
}

/// Protocol for decoders that can decode Codable types from Data.
///
/// This protocol allows `CodableFileMonitor` to work with any decoder that can
/// parse `Data` into `Decodable` types. Foundation's `JSONDecoder` and
/// `PropertyListDecoder` conform to this protocol automatically via extensions.
///
/// ## Example
/// ```swift
/// struct CustomDecoder: CFMDataDecoder {
///     func decodeFromData<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
///         // Your custom decoding logic here
///         return decodedValue
///     }
/// }
/// ```
public protocol CFMDataDecoder {
  /// Decodes a top-level value of the given type from the given Data representation.
  ///
  /// - Parameters:
  ///   - type: The type of the value to decode.
  ///   - data: The data to decode from.
  /// - Returns: A value of the requested type.
  /// - Throws: An error if any value throws an error during decoding.
  func decodeFromData<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

// MARK: - Foundation Extensions

extension JSONEncoder: CFMDataEncoder {
  public func encodeToData<T>(_ value: T) throws -> Data where T: Encodable {
    try self.encode(value)
  }
}

extension JSONDecoder: CFMDataDecoder {
  public func decodeFromData<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
    try self.decode(type, from: data)
  }
}

extension PropertyListEncoder: CFMDataEncoder {
  public func encodeToData<T>(_ value: T) throws -> Data where T: Encodable {
    try self.encode(value)
  }
}

extension PropertyListDecoder: CFMDataDecoder {
  public func decodeFromData<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
    try self.decode(type, from: data)
  }
}

/// A generic file monitor that automatically manages Codable data with file persistence.
///
/// `CodableFileMonitor` provides a type-safe, thread-safe way to monitor and persist
/// Codable data structures to files. It automatically saves changes and detects external
/// file modifications using polling (500ms intervals).
///
/// ## Features
/// - **Generic Type Safety**: Works with any `Codable` type
/// - **Custom Codecs**: Supports any encoder/decoder conforming to `CFMDataEncoder`/`CFMDataDecoder`
/// - **Automatic Persistence**: Changes to `data` property trigger automatic saves
/// - **External Change Detection**: Monitors file system for external modifications
/// - **Thread Safety**: Uses `NSLock` for safe concurrent access
/// - **Swift Observation**: Integrates with `@Observable` for SwiftUI
/// - **Swift 6 Concurrency**: Full async/await support with `@unchecked Sendable`
///
/// ## Basic Usage
/// ```swift
/// struct AppConfig: Codable {
///     let name: String
///     let version: String
/// }
///
/// let monitor = CodableFileMonitor(
///     fileURL: configURL,
///     defaultValue: AppConfig(name: "MyApp", version: "1.0")
/// )
///
/// try await monitor.startMonitoring()
/// monitor.data = AppConfig(name: "UpdatedApp", version: "2.0")  // Auto-saves
/// await monitor.stopMonitoring()
/// ```
///
/// ## Custom Codecs
/// ```swift
/// let plistMonitor = CodableFileMonitor(
///     fileURL: plistURL,
///     defaultValue: config,
///     encoder: PropertyListEncoder(),
///     decoder: PropertyListDecoder()
/// )
/// ```
///
/// ## SwiftUI Integration
/// The `@Observable` macro makes this class perfect for SwiftUI:
/// ```swift
/// struct ConfigView: View {
///     let monitor: CodableFileMonitor<AppConfig, JSONEncoder, JSONDecoder>
///
///     var body: some View {
///         Text("App: \(monitor.data.name)")  // Auto-updates
///     }
/// }
/// ```
@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, watchOS 10.0, tvOS 17.0, *)
@Observable
public final class CodableFileMonitor<
  T: Codable,
  Encoder: CFMDataEncoder,
  Decoder: CFMDataDecoder
>: @unchecked Sendable {
  // MARK: Lifecycle

  // MARK: - Initialization

  /// Creates a new file monitor with custom encoder and decoder.
  ///
  /// This initializer allows you to specify custom encoders and decoders for
  /// different file formats (JSON, PropertyList, etc.).
  ///
  /// - Parameters:
  ///   - fileURL: The URL of the file to monitor. Parent directories will be created if needed.
  ///   - defaultValue: The default value to use when the file doesn't exist or fails to load.
  ///   - encoder: The encoder to use for saving data. Must conform to `CFMDataEncoder`.
  ///   - decoder: The decoder to use for loading data. Must conform to `CFMDataDecoder`.
  ///
  /// ## Example
  /// ```swift
  /// let monitor = CodableFileMonitor(
  ///     fileURL: URL(fileURLWithPath: "/path/to/config.plist"),
  ///     defaultValue: MyConfig.default,
  ///     encoder: PropertyListEncoder(),
  ///     decoder: PropertyListDecoder()
  /// )
  /// ```
  public init(
    fileURL: URL,
    defaultValue: T,
    encoder: Encoder,
    decoder: Decoder
  ) {
    self.fileURL = fileURL
    self.defaultValue = defaultValue
    self.dataStorage = DataStorage(defaultValue: defaultValue)
    self._encoder = encoder
    self._decoder = decoder
  }

  // MARK: - Deinitialization

  deinit {
    // Synchronously cancel monitoring task
    monitoringTask?.cancel()
  }

  // MARK: Public

  /// The URL of the file being monitored.
  ///
  /// This is the file path where data will be saved and from which external
  /// changes will be detected. Parent directories will be created automatically
  /// when saving if they don't exist.
  ///
  /// - Note: This property is not observed for changes to avoid unnecessary notifications.
  @ObservationIgnored public let fileURL: URL

  /// The default value used when the file doesn't exist or fails to load.
  ///
  /// This value is used in the following scenarios:
  /// - When the monitored file doesn't exist at startup
  /// - When the file contains invalid data that cannot be decoded
  /// - As a fallback during error recovery
  ///
  /// - Note: This property is not observed for changes to avoid unnecessary notifications.
  @ObservationIgnored public let defaultValue: T

  /// Actor-based storage for thread-safe data access
  @ObservationIgnored private let dataStorage: DataStorage

  /// The current data being monitored.
  ///
  /// This property is fully observable and changes trigger automatic file persistence.
  /// When you assign a new value, it will be automatically saved to the file system
  /// asynchronously.
  ///
  /// ## Important Notes for Struct-Based Types
  /// For struct-based Codable types, nested property changes require setting the entire
  /// data property. Direct mutation of nested properties won't trigger observation or auto-save.
  ///
  /// ## Examples
  /// ```swift
  /// // ✅ This will trigger observation and auto-save:
  /// var config = monitor.data
  /// config.appName = "New Name"
  /// monitor.data = config
  ///
  /// // ❌ This won't work for structs (compilation error):
  /// // monitor.data.appName = "New Name"
  ///
  /// // ✅ For SwiftUI bindings, use this pattern:
  /// Toggle("Debug Mode", isOn: Binding(
  ///     get: { monitor.data.debugEnabled },
  ///     set: { newValue in
  ///         var config = monitor.data
  ///         config.debugEnabled = newValue
  ///         monitor.data = config  // Triggers observation + auto-save
  ///     }
  /// ))
  /// ```
  ///
  /// - Note: Changes to this property are automatically observed by SwiftUI and other
  ///   observation clients, making it perfect for reactive UI updates.
  public var data: T {
    get {
      dataStorage.currentData
    }
    set {
      dataStorage.updateDataSync(newValue)
      Task {
        await saveData()
      }
    }
  }

  /// Indicates whether file system monitoring is currently active.
  ///
  /// Returns `true` if `startMonitoring()` has been called and the monitoring task
  /// is running. Returns `false` if monitoring hasn't started or has been stopped.
  ///
  /// ## Example
  /// ```swift
  /// print("Monitoring: \(monitor.isMonitoring)")  // false
  /// try await monitor.startMonitoring()
  /// print("Monitoring: \(monitor.isMonitoring)")  // true
  /// await monitor.stopMonitoring()
  /// print("Monitoring: \(monitor.isMonitoring)")  // false
  /// ```
  ///
  /// - Note: This property can be used to prevent multiple calls to `startMonitoring()`
  ///   or to check status before calling `stopMonitoring()`.
  public var isMonitoring: Bool {
    monitoringTask?.isCancelled == false
  }

  /// The last known modification date of the monitored file.
  ///
  /// This property is updated whenever the file is successfully read or written.
  /// It's used internally to detect external file changes and avoid unnecessary
  /// reload operations.
  ///
  /// - Returns: The file's last modification date, or `nil` if:
  ///   - The file doesn't exist
  ///   - The file hasn't been accessed yet
  ///   - An error occurred reading file attributes
  ///
  /// ## Example
  /// ```swift
  /// if let lastMod = monitor.lastModificationDate {
  ///     print("File last modified: \(lastMod.formatted())")
  /// } else {
  ///     print("File modification date unknown")
  /// }
  /// ```
  public var lastModificationDate: Date? {
    dataStorage.currentModificationDate
  }

  // MARK: - Monitoring

  /// Starts file system monitoring and loads initial data from the file.
  ///
  /// This method performs the following operations:
  /// 1. Loads initial data from the file (or uses default value if file doesn't exist)
  /// 2. Starts a background polling task that checks for external file changes every 500ms
  /// 3. Returns immediately after starting the monitoring task
  ///
  /// ## Behavior
  /// - If the file exists, its contents are loaded and decoded
  /// - If the file doesn't exist, the default value is used and the file will be created on first save
  /// - If the file contains invalid data, a `CodableFileMonitorError.decodingFailed` error is thrown
  /// - Multiple calls to this method are safe - subsequent calls are ignored if monitoring is already active
  ///
  /// ## Example
  /// ```swift
  /// do {
  ///     try await monitor.startMonitoring()
  ///     print("Monitoring started successfully")
  /// } catch {
  ///     print("Failed to start monitoring: \(error)")
  /// }
  /// ```
  ///
  /// - Throws: `CodableFileMonitorError.decodingFailed` if the file contains invalid data
  /// - Note: Always call `stopMonitoring()` when you're done to clean up resources
  public func startMonitoring() async throws {
    guard monitoringTask?.isCancelled != false else { return }

    // Load initial data
    try await loadData()

    // Start file monitoring task
    monitoringTask = Task {
      await monitorFileChanges()
    }
  }

  /// Stops file system monitoring and cancels the background monitoring task.
  ///
  /// This method immediately cancels the background polling task and cleans up resources.
  /// It's safe to call this method multiple times or when monitoring isn't active.
  ///
  /// ## Example
  /// ```swift
  /// await monitor.stopMonitoring()
  /// print("Monitoring stopped")
  /// ```
  ///
  /// - Note: This method completes immediately and doesn't wait for the background task to finish
  public func stopMonitoring() async {
    monitoringTask?.cancel()
    monitoringTask = nil
  }

  /// Manually reloads data from the file, bypassing the automatic polling mechanism.
  ///
  /// This method forces an immediate reload of the file contents, regardless of
  /// modification timestamps. Use this when you know the file has been changed
  /// externally and want to update immediately without waiting for the next
  /// polling cycle.
  ///
  /// ## Behavior
  /// - If the file exists, its contents are loaded and decoded
  /// - If the file doesn't exist, the default value is used
  /// - The `data` property is updated with the loaded/default value
  /// - The `lastModificationDate` is updated
  ///
  /// ## Example
  /// ```swift
  /// do {
  ///     try await monitor.reloadData()
  ///     print("Data reloaded: \(monitor.data)")
  /// } catch {
  ///     print("Failed to reload: \(error)")
  /// }
  /// ```
  ///
  /// - Throws: `CodableFileMonitorError.decodingFailed` if the file contains invalid data
  public func reloadData() async throws {
    try await loadData()
  }

  /// Manually saves the current data to the file.
  ///
  /// This method forces an immediate save of the current `data` property to the file,
  /// bypassing the automatic save mechanism. The save operation is performed atomically
  /// to prevent file corruption.
  ///
  /// ## Behavior
  /// - Creates parent directories if they don't exist
  /// - Encodes the current data using the configured encoder
  /// - Writes to the file using atomic operations
  /// - Updates the `lastModificationDate` property
  /// - Errors are logged but don't throw (for compatibility with automatic saves)
  ///
  /// ## Example
  /// ```swift
  /// monitor.data = newConfiguration
  /// await monitor.saveData()  // Force immediate save
  /// print("Data saved successfully")
  /// ```
  ///
  /// - Note: This method doesn't throw errors. Check the console output for error messages.
  public func saveData() async {
    do {
      try await saveDataToFile()
    } catch {
      // Handle save errors - could add logging or error reporting here
      print("Failed to save data to \(fileURL.path): \(error)")
    }
  }

  // MARK: Internal

  /// Thread-safe data storage using actor pattern
  private final class DataStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var _data: T
    private var _modificationDate: Date?

    init(defaultValue: T) {
      self._data = defaultValue
      self._modificationDate = nil
    }

    var currentData: T {
      lock.lock()
      defer { lock.unlock() }
      return _data
    }

    var currentModificationDate: Date? {
      lock.lock()
      defer { lock.unlock() }
      return _modificationDate
    }

    func updateDataSync(_ newData: T) {
      lock.lock()
      defer { lock.unlock() }
      self._data = newData
    }

    func updateData(_ newData: T, modificationDate: Date?) async {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        lock.lock()
        defer {
          lock.unlock()
          continuation.resume()
        }
        self._data = newData
        self._modificationDate = modificationDate
      }
    }
  }

  // MARK: Private

  /// Task for monitoring file changes
  @ObservationIgnored private var monitoringTask: Task<Void, Never>?

  /// Custom encoder for saving data
  @ObservationIgnored private let _encoder: Encoder

  /// Custom decoder for loading data
  @ObservationIgnored private let _decoder: Decoder

  // MARK: - Private Methods

  /// Creates parent directory if needed
  private func createParentDirectoryIfNeeded() async throws {
    let parentURL = fileURL.deletingLastPathComponent()
    let fileManager = FileManager.default

    var isDirectory: ObjCBool = false
    if !fileManager.fileExists(atPath: parentURL.path, isDirectory: &isDirectory) {
      try fileManager.createDirectory(
        at: parentURL,
        withIntermediateDirectories: true,
        attributes: nil
      )
    }
  }

  /// Loads data from file
  private func loadData() async throws {
    let fileManager = FileManager.default

    // Check if file exists
    guard fileManager.fileExists(atPath: fileURL.path) else {
      // Use default value if file doesn't exist
      await dataStorage.updateData(defaultValue, modificationDate: nil)
      return
    }

    do {
      // Get file attributes for modification date
      let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
      let modificationDate = attributes[.modificationDate] as? Date

      // Only reload if file has been modified
      let lastMod = dataStorage.currentModificationDate
      if let lastMod = lastMod,
        let fileMod = modificationDate,
        fileMod <= lastMod
      {
        return  // File hasn't changed
      }

      // Load and decode data
      let fileData = try Data(contentsOf: fileURL)
      let decodedData = try _decoder.decodeFromData(T.self, from: fileData)

      // Update properties with actor
      await dataStorage.updateData(decodedData, modificationDate: modificationDate)

    } catch {
      throw CodableFileMonitorError.decodingFailed(error)
    }
  }

  /// Saves current data to file
  private func saveDataToFile() async throws {
    do {
      // Ensure parent directory exists
      try await createParentDirectoryIfNeeded()

      // Get current data from storage
      let currentData = dataStorage.currentData

      // Encode data
      let encodedData = try _encoder.encodeToData(currentData)

      // Write to file atomically
      try encodedData.write(to: fileURL, options: Data.WritingOptions.atomic)

      // Update modification date in actor
      let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      let modificationDate = attributes[.modificationDate] as? Date
      await dataStorage.updateData(currentData, modificationDate: modificationDate)

    } catch {
      throw CodableFileMonitorError.encodingFailed(error)
    }
  }

  /// Monitors file changes using polling
  private func monitorFileChanges() async {
    while !Task.isCancelled {
      do {
        try await loadData()

        // Wait before next check (0.5s)
        try await Task.sleep(nanoseconds: 500_000_000)
      } catch {
        // Handle errors silently or log them
        print("Error monitoring file \(fileURL.path): \(error)")
        try? await Task.sleep(nanoseconds: 500_000_000)
      }
    }
  }
}

// MARK: - Error Handling

/// Errors that can occur during file monitoring operations.
///
/// These errors provide specific information about what went wrong during
/// file operations, encoding, or decoding.
public enum CodableFileMonitorError: LocalizedError {
  /// The monitored file was not found.
  ///
  /// This error typically occurs during manual operations when attempting
  /// to read a file that doesn't exist. During normal monitoring, missing
  /// files are handled gracefully by using the default value.
  case fileNotFound

  /// The file contains data that cannot be processed.
  ///
  /// This error occurs when the file exists but contains data that doesn't
  /// match the expected format or structure.
  case invalidData

  /// Failed to encode data for writing to the file.
  ///
  /// This error wraps the underlying encoding error and indicates that the
  /// current data couldn't be serialized using the configured encoder.
  ///
  /// - Parameter Error: The underlying encoding error.
  case encodingFailed(Error)

  /// Failed to decode data when reading from the file.
  ///
  /// This error wraps the underlying decoding error and indicates that the
  /// file contents couldn't be deserialized using the configured decoder.
  ///
  /// - Parameter Error: The underlying decoding error.
  case decodingFailed(Error)

  /// A file system error occurred.
  ///
  /// This error wraps underlying file system errors such as permission
  /// issues, disk full, or other I/O problems.
  ///
  /// - Parameter Error: The underlying file system error.
  case fileSystemError(Error)

  /// A localized message describing what error occurred.
  public var errorDescription: String? {
    switch self {
    case .fileNotFound:
      return "The monitored file was not found"
    case .invalidData:
      return "The file contains invalid data"
    case .encodingFailed(let error):
      return "Failed to encode data: \(error.localizedDescription)"
    case .decodingFailed(let error):
      return "Failed to decode data: \(error.localizedDescription)"
    case .fileSystemError(let error):
      return "File system error: \(error.localizedDescription)"
    }
  }
}

// MARK: - Type Aliases for Common Usage

/// Type alias for `CodableFileMonitor` using JSON codecs.
///
/// This is the most common usage pattern, providing a convenient way to create
/// file monitors that use JSON for serialization. The JSON encoder is configured
/// with pretty printing and sorted keys for human-readable output.
///
/// ## Example
/// ```swift
/// let jsonMonitor: JSONCodableFileMonitor<AppConfig> = CodableFileMonitor(
///     fileURL: configURL,
///     defaultValue: AppConfig.default
/// )
/// ```
///
/// This is equivalent to:
/// ```swift
/// let jsonMonitor = CodableFileMonitor<AppConfig, JSONEncoder, JSONDecoder>(
///     fileURL: configURL,
///     defaultValue: AppConfig.default,
///     encoder: JSONEncoder(),
///     decoder: JSONDecoder()
/// )
/// ```
@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, watchOS 10.0, tvOS 17.0, *)
public typealias JSONCodableFileMonitor<T: Codable> = CodableFileMonitor<
  T, JSONEncoder, JSONDecoder
>

@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, watchOS 10.0, tvOS 17.0, *)
extension JSONCodableFileMonitor where Encoder == JSONEncoder, Decoder == JSONDecoder {
  /// Creates a new file monitor using JSON codecs (convenience initializer).
  ///
  /// This convenience initializer automatically configures JSON encoder and decoder
  /// with pretty printing and sorted keys for human-readable output.
  ///
  /// - Parameters:
  ///   - fileURL: The URL of the JSON file to monitor. Parent directories will be created if needed.
  ///   - defaultValue: The default value to use when the file doesn't exist or fails to load.
  ///
  /// ## Example
  /// ```swift
  /// let monitor = CodableFileMonitor(
  ///     fileURL: URL(fileURLWithPath: "/path/to/config.json"),
  ///     defaultValue: AppConfig.default
  /// )
  /// ```
  ///
  /// - Note: This initializer is only available when `Encoder` is `JSONEncoder` and `Decoder` is `JSONDecoder`.
  public convenience init(
    fileURL: URL,
    defaultValue: T
  ) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let decoder = JSONDecoder()
    self.init(fileURL: fileURL, defaultValue: defaultValue, encoder: encoder, decoder: decoder)
  }
}

/// Type alias for `CodableFileMonitor` using PropertyList codecs.
///
/// This type alias provides a convenient way to create file monitors that use
/// Apple's PropertyList format for serialization, which is commonly used in
/// macOS and iOS applications.
///
/// ## Example
/// ```swift
/// let plistMonitor: PlistCodableFileMonitor<UserSettings> = CodableFileMonitor(
///     fileURL: settingsURL,
///     defaultValue: UserSettings.default,
///     encoder: PropertyListEncoder(),
///     decoder: PropertyListDecoder()
/// )
/// ```
///
/// This is equivalent to:
/// ```swift
/// let plistMonitor = CodableFileMonitor<UserSettings, PropertyListEncoder, PropertyListDecoder>(
///     fileURL: settingsURL,
///     defaultValue: UserSettings.default,
///     encoder: PropertyListEncoder(),
///     decoder: PropertyListDecoder()
/// )
/// ```
///
/// - Note: PropertyList format supports fewer data types than JSON, so ensure
///   your Codable types are compatible with PropertyList serialization.
@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, watchOS 10.0, tvOS 17.0, *)
public typealias PlistCodableFileMonitor<T: Codable> = CodableFileMonitor<
  T, PropertyListEncoder, PropertyListDecoder
>

@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, watchOS 10.0, tvOS 17.0, *)
extension PlistCodableFileMonitor
where Encoder == PropertyListEncoder, Decoder == PropertyListDecoder {
  /// Creates a new file monitor using PropertyList codecs (convenience initializer).
  ///
  /// This convenience initializer automatically configures PropertyList encoder and decoder
  /// for use with PropertyList serialization.
  ///
  /// - Parameters:
  ///   - fileURL: The URL of the PropertyList file to monitor. Parent directories will be created if needed.
  ///   - defaultValue: The default value to use when the file doesn't exist or fails to load.
  ///
  /// ## Example
  /// ```swift
  /// let monitor = CodableFileMonitor(
  ///     fileURL: URL(fileURLWithPath: "/path/to/settings.plist"),
  ///     defaultValue: UserSettings.default
  /// )
  /// ```
  ///
  /// - Note: This initializer is only available when `Encoder` is `PropertyListEncoder` and `Decoder` is `PropertyListDecoder`.
  public convenience init(
    fileURL: URL,
    defaultValue: T
  ) {
    self.init(
      fileURL: fileURL,
      defaultValue: defaultValue,
      encoder: PropertyListEncoder(),
      decoder: PropertyListDecoder()
    )
  }
}
