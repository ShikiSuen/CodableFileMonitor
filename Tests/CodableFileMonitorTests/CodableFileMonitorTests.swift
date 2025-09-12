// (c) 2025 and onwards Shiki Suen (MIT License).
// ====================
// This code is released under the SPDX-License-Identifier: `MIT`.

import Foundation
import Testing

@testable import CodableFileMonitor

// MARK: - Test Data Structures

struct TestConfig: Codable, Equatable {
  let name: String
  let version: Int
  let enabled: Bool

  static let defaultValue = TestConfig(name: "default", version: 1, enabled: false)
}

struct ComplexTestData: Codable, Equatable {
  let id: UUID
  let timestamps: [Date]
  let metadata: [String: String]

  static let defaultValue = ComplexTestData(
    id: UUID(),
    timestamps: [],
    metadata: [:]
  )
}

// MARK: - Test Suite

@Suite
struct CodableFileMonitorTests {
  @Test("CodableFileMonitor: Basic initialization and data management")
  func testBasicInitialization() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: TestConfig.defaultValue
    )

    // Check initial state
    #expect(monitor.data == TestConfig.defaultValue)
    #expect(monitor.fileURL == tempURL)
    #expect(!monitor.isMonitoring)
    #expect(monitor.lastModificationDate == nil)
  }

  @Test("CodableFileMonitor: File creation and data persistence")
  func testDataPersistence() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: TestConfig.defaultValue
    )

    // Modify data - should trigger automatic save
    let newConfig = TestConfig(name: "test", version: 2, enabled: true)
    await MainActor.run {
      monitor.data = newConfig
    }

    // Wait a bit for the async save to complete
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s

    // Verify file was created and contains correct data
    #expect(FileManager.default.fileExists(atPath: tempURL.path(percentEncoded: false)))

    let savedData = try Data(contentsOf: tempURL)
    let decodedConfig = try JSONDecoder().decode(TestConfig.self, from: savedData)
    #expect(decodedConfig == newConfig)
  }

  @Test("CodableFileMonitor: Monitoring and external file changes")
  func testFileMonitoring() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Create initial file with data
    let initialConfig = TestConfig(name: "initial", version: 1, enabled: false)
    let initialData = try JSONEncoder().encode(initialConfig)
    try initialData.write(to: tempURL)

    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: TestConfig.defaultValue
    )

    // Start monitoring
    try await monitor.startMonitoring()
    #expect(monitor.isMonitoring)
    #expect(monitor.data == initialConfig)

    // Externally modify the file
    let modifiedConfig = TestConfig(name: "modified", version: 3, enabled: true)
    let modifiedData = try JSONEncoder().encode(modifiedConfig)

    // Add small delay to ensure different modification time
    try await Task.sleep(nanoseconds: 10_000_000)  // 0.01s
    try modifiedData.write(to: tempURL)

    // Wait for the monitor to detect changes
    try await Task.sleep(nanoseconds: 800_000_000)  // 0.8s (longer than polling interval)

    // Verify data was updated
    #expect(monitor.data == modifiedConfig)

    // Clean up
    await monitor.stopMonitoring()
    #expect(!monitor.isMonitoring)
  }

  @Test("CodableFileMonitor: Complex data types")
  func testComplexDataTypes() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: ComplexTestData.defaultValue
    )

    // Create complex data
    let complexData = ComplexTestData(
      id: UUID(),
      timestamps: [Date(), Date().addingTimeInterval(-3600)],
      metadata: ["author": "test", "version": "1.0"]
    )

    await MainActor.run {
      monitor.data = complexData
    }

    // Wait for save
    try await Task.sleep(nanoseconds: 100_000_000)

    // Verify persistence
    let savedData = try Data(contentsOf: tempURL)
    let decodedData = try JSONDecoder().decode(ComplexTestData.self, from: savedData)

    #expect(decodedData.id == complexData.id)
    #expect(decodedData.metadata == complexData.metadata)
    #expect(decodedData.timestamps.count == complexData.timestamps.count)
  }

  @Test("CodableFileMonitor: Error handling for corrupt files")
  func testErrorHandling() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Write invalid JSON to file
    let invalidData = "invalid json data".data(using: .utf8)!
    try invalidData.write(to: tempURL)

    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: TestConfig.defaultValue
    )

    // Starting monitoring with invalid file should throw
    do {
      try await monitor.startMonitoring()
      #expect(Bool(false), "Should have thrown an error for invalid file")
    } catch {
      #expect(error is CodableFileMonitorError)
    }
  }

  @Test("CodableFileMonitor: Manual reload functionality")
  func testManualReload() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Create initial file
    let initialConfig = TestConfig(name: "initial", version: 1, enabled: false)
    let initialData = try JSONEncoder().encode(initialConfig)
    try initialData.write(to: tempURL)

    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: TestConfig.defaultValue
    )

    // Load initial data
    try await monitor.reloadData()
    #expect(monitor.data == initialConfig)

    // Externally modify file
    let modifiedConfig = TestConfig(name: "modified", version: 2, enabled: true)
    let modifiedData = try JSONEncoder().encode(modifiedConfig)

    // Add small delay to ensure different modification time
    try await Task.sleep(nanoseconds: 10_000_000)  // 0.01s
    try modifiedData.write(to: tempURL)

    // Manual reload should pick up changes
    try await monitor.reloadData()
    #expect(monitor.data == modifiedConfig)
  }

  @Test("CodableFileMonitor: Concurrent access safety")
  func testConcurrentAccess() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: TestConfig.defaultValue
    )

    try await monitor.startMonitoring()

    // Perform concurrent data modifications
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          await MainActor.run {
            let config = TestConfig(name: "config\(i)", version: i, enabled: i % 2 == 0)
            monitor.data = config
          }
        }
      }
    }

    // Wait for operations to complete
    try await Task.sleep(nanoseconds: 200_000_000)

    // Verify file exists and contains valid data
    #expect(FileManager.default.fileExists(atPath: tempURL.path(percentEncoded: false)))

    let savedData = try Data(contentsOf: tempURL)
    let _ = try JSONDecoder().decode(TestConfig.self, from: savedData)  // Should not throw

    await monitor.stopMonitoring()
  }

  @Test("CodableFileMonitor: No file overwrite during initialization - file not exists")
  func testNoFileOverwriteInitNonExistentFile() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Ensure file doesn't exist
    #expect(!FileManager.default.fileExists(atPath: tempURL.path(percentEncoded: false)))

    // Create monitor with default value
    let defaultConfig = TestConfig(name: "default-test", version: 99, enabled: true)
    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: defaultConfig
    )

    // Verify initialization doesn't create file
    #expect(!FileManager.default.fileExists(atPath: tempURL.path(percentEncoded: false)))
    #expect(monitor.data == defaultConfig)

    // Even after startMonitoring, file should not be created if it doesn't exist
    try await monitor.startMonitoring()
    #expect(!FileManager.default.fileExists(atPath: tempURL.path(percentEncoded: false)))
    #expect(monitor.data == defaultConfig)

    await monitor.stopMonitoring()
  }

  @Test("CodableFileMonitor: No file overwrite during initialization - existing file")
  func testNoFileOverwriteInitExistingFile() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Create existing file with different content than default
    let existingConfig = TestConfig(name: "existing-content", version: 42, enabled: false)
    let existingData = try JSONEncoder().encode(existingConfig)
    try existingData.write(to: tempURL)

    // Get original file modification date
    let originalAttributes = try FileManager.default.attributesOfItem(
      atPath: tempURL.path(percentEncoded: false))
    let originalModDate = originalAttributes[.modificationDate] as! Date

    // Create monitor with different default value
    let defaultConfig = TestConfig(name: "default-different", version: 1, enabled: true)
    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: defaultConfig
    )

    // Check that init doesn't change the file
    let postInitAttributes = try FileManager.default.attributesOfItem(
      atPath: tempURL.path(percentEncoded: false))
    let postInitModDate = postInitAttributes[.modificationDate] as! Date
    #expect(postInitModDate == originalModDate)

    // Verify file content hasn't changed
    let fileData = try Data(contentsOf: tempURL)
    let fileConfig = try JSONDecoder().decode(TestConfig.self, from: fileData)
    #expect(fileConfig == existingConfig)

    // Start monitoring and verify file is loaded, not overwritten
    try await monitor.startMonitoring()

    // File should still have original modification date
    let postStartAttributes = try FileManager.default.attributesOfItem(
      atPath: tempURL.path(percentEncoded: false))
    let postStartModDate = postStartAttributes[.modificationDate] as! Date
    #expect(postStartModDate == originalModDate)

    // Monitor should have loaded existing data, not used default
    #expect(monitor.data == existingConfig)
    #expect(monitor.data != defaultConfig)

    await monitor.stopMonitoring()
  }

  @Test("CodableFileMonitor: Custom Property List Codecs")
  func testPropertyListCodecs() async throws {
    let tempURL = createTempPlistFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Create monitor with PropertyList codecs
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    let decoder = PropertyListDecoder()

    let monitor = CodableFileMonitor(
      fileURL: tempURL,
      defaultValue: TestConfig.defaultValue,
      encoder: encoder,
      decoder: decoder
    )

    // Test data persistence with plist format
    let testConfig = TestConfig(name: "plist-test", version: 42, enabled: true)
    monitor.data = testConfig

    // Wait for automatic save
    try await Task.sleep(nanoseconds: 100_000_000)

    // Verify file was created and contains XML plist data
    #expect(FileManager.default.fileExists(atPath: tempURL.path(percentEncoded: false)))

    let fileContent = try String(contentsOf: tempURL, encoding: .utf8)
    #expect(fileContent.contains("<?xml version="))
    #expect(fileContent.contains("plist-test"))

    // Test reloading
    try await monitor.startMonitoring()
    #expect(monitor.data == testConfig)

    await monitor.stopMonitoring()
  }

  @Test("CodableFileMonitor: Force-load mechanism - immediate data access after initialization")
  func testForceLoadMechanism() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Create a file with specific data that differs from default
    let fileConfig = TestConfig(name: "file-data", version: 999, enabled: true)
    let fileData = try JSONEncoder().encode(fileConfig)
    try fileData.write(to: tempURL)

    // Create monitor with different default value
    let defaultConfig = TestConfig(name: "default-data", version: 1, enabled: false)
    let monitor = JSONCodableFileMonitor(
      fileURL: tempURL,
      defaultValue: defaultConfig
    )

    // CRITICAL TEST: Access monitor.data immediately after initialization
    // WITHOUT calling startMonitoring() first
    // This should return the file data, not the default data
    // This behavior depends on the force-load mechanism in the initializer
    #expect(monitor.data == fileConfig, "Force-load mechanism should load file data during initialization")
    #expect(monitor.data != defaultConfig, "Should not use default value when file exists")

    // Verify the file hasn't been modified (timestamp check)
    let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path(percentEncoded: false))
    let modDate = attributes[.modificationDate] as! Date
    
    // Even after accessing data, file should not be modified
    try await Task.sleep(nanoseconds: 10_000_000)  // Small delay
    let newAttributes = try FileManager.default.attributesOfItem(atPath: tempURL.path(percentEncoded: false))
    let newModDate = newAttributes[.modificationDate] as! Date
    #expect(newModDate == modDate, "File should not be modified by force-load mechanism")
  }

  @Test("CodableFileMonitor: Demonstrates why force-load is necessary vs startMonitoring")
  func testForceLoadVsStartMonitoring() async throws {
    let tempURL = createTempFileURL()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Create a file with specific data
    let fileConfig = TestConfig(name: "file-content", version: 42, enabled: true)
    let fileData = try JSONEncoder().encode(fileConfig)
    try fileData.write(to: tempURL)

    // Test 1: With force-load (current behavior) - immediate access works
    do {
      let monitor = JSONCodableFileMonitor(
        fileURL: tempURL,
        defaultValue: TestConfig(name: "default", version: 1, enabled: false)
      )
      
      // This should work immediately thanks to force-load
      #expect(monitor.data == fileConfig, "Force-load allows immediate access to file data")
    }

    // Test 2: Simulate what would happen if we relied only on startMonitoring
    // By demonstrating the timing difference
    do {
      let monitor = JSONCodableFileMonitor(
        fileURL: tempURL,
        defaultValue: TestConfig(name: "default", version: 1, enabled: false)
      )
      
      // The monitor already has the file data due to force-load
      let dataBeforeStartMonitoring = monitor.data
      
      // Start monitoring (which would normally be required to load data)
      try await monitor.startMonitoring()
      let dataAfterStartMonitoring = monitor.data
      
      // Both should be the same due to force-load
      #expect(dataBeforeStartMonitoring == dataAfterStartMonitoring)
      #expect(dataBeforeStartMonitoring == fileConfig)
      
      await monitor.stopMonitoring()
    }
  }
}

// MARK: - Helper Functions

private func createTempFileURL() -> URL {
  let tempDir = FileManager.default.temporaryDirectory
  let fileName = "CodableFileMonitor_Test_\(UUID().uuidString).json"
  return tempDir.appendingPathComponent(fileName)
}

private func createTempPlistFileURL() -> URL {
  let tempDir = FileManager.default.temporaryDirectory
  let fileName = "CodableFileMonitor_Test_\(UUID().uuidString).plist"
  return tempDir.appendingPathComponent(fileName)
}
