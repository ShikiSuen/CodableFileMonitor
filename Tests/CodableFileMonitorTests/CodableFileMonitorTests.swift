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
    #expect(FileManager.default.fileExists(atPath: tempURL.path))

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
    try modifiedData.write(to: tempURL)

    // Wait for the monitor to detect changes
    try await Task.sleep(nanoseconds: 700_000_000)  // 0.7s (longer than polling interval)

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
      #expect(error is JSONCodableFileMonitor<TestConfig>.CodableFileMonitorError)
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
    #expect(FileManager.default.fileExists(atPath: tempURL.path))

    let savedData = try Data(contentsOf: tempURL)
    let _ = try JSONDecoder().decode(TestConfig.self, from: savedData)  // Should not throw

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
    #expect(FileManager.default.fileExists(atPath: tempURL.path))

    let fileContent = try String(contentsOf: tempURL, encoding: .utf8)
    #expect(fileContent.contains("<?xml version="))
    #expect(fileContent.contains("plist-test"))

    // Test reloading
    try await monitor.startMonitoring()
    #expect(monitor.data == testConfig)

    await monitor.stopMonitoring()
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
