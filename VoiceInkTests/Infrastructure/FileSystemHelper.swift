import Foundation
import XCTest

/// Helper utilities for file system testing
@available(macOS 14.0, *)
final class FileSystemHelper {
    
    // MARK: - Temporary Directory Management
    
    /// Create an isolated temporary directory for tests
    static func createIsolatedDirectory(prefix: String = "VoiceInkTest") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        
        try? FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        return tempDir
    }
    
    /// Clean up a directory and all its contents
    static func cleanupDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
    
    /// Create a directory structure for testing
    static func createTestStructure(in baseDirectory: URL, structure: [String]) throws {
        for path in structure {
            let fullPath = baseDirectory.appendingPathComponent(path)
            
            if path.hasSuffix("/") {
                // It's a directory
                try FileManager.default.createDirectory(
                    at: fullPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } else {
                // It's a file
                let directoryPath = fullPath.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: directoryPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try Data().write(to: fullPath)
            }
        }
    }
    
    // MARK: - File Operations Testing
    
    /// Assert that a file exists at the given path
    static func assertFileExists(
        at url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "File does not exist at: \(url.path)",
            file: file,
            line: line
        )
    }
    
    /// Assert that a file does not exist at the given path
    static func assertFileDoesNotExist(
        at url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "File exists at: \(url.path)",
            file: file,
            line: line
        )
    }
    
    /// Assert that a directory is empty
    static func assertDirectoryEmpty(
        _ directory: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        
        XCTAssertTrue(
            contents.isEmpty,
            "Directory is not empty. Contains: \(contents.map { $0.lastPathComponent })",
            file: file,
            line: line
        )
    }
    
    /// Count files in a directory
    static func countFiles(in directory: URL, matching predicate: (URL) -> Bool = { _ in true }) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        
        var count = 0
        for case let fileURL as URL in enumerator {
            if predicate(fileURL) {
                count += 1
            }
        }
        
        return count
    }
    
    // MARK: - File Handle Testing
    
    /// Track open file handles
    class FileHandleTracker {
        private var handles: Set<Int32> = []
        private let lock = NSLock()
        
        func trackHandle(_ handle: Int32) {
            lock.lock()
            defer { lock.unlock() }
            handles.insert(handle)
        }
        
        func untrackHandle(_ handle: Int32) {
            lock.lock()
            defer { lock.unlock() }
            handles.remove(handle)
        }
        
        var openHandleCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return handles.count
        }
        
        func assertAllHandlesClosed(
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let count = openHandleCount
            XCTAssertEqual(
                count,
                0,
                "Expected all file handles to be closed, but \(count) remain open",
                file: file,
                line: line
            )
        }
    }
    
    // MARK: - Disk Space Simulation
    
    /// Simulate disk full condition
    static func simulateDiskFull(in directory: URL) throws {
        // Create a very large file to fill up available space
        // Note: This is for testing purposes only and should be used carefully
        let testFile = directory.appendingPathComponent("disk_full_test.bin")
        
        // Get available space
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let freeSpace = attributes[.systemFreeSize] as? Int64 else {
            throw FileSystemError.cannotDetermineSpace
        }
        
        // Fill most of it (leave 100MB)
        let sizeToWrite = max(0, freeSpace - 100_000_000)
        
        let data = Data(count: Int(sizeToWrite))
        try data.write(to: testFile)
    }
    
    // MARK: - Permission Testing
    
    /// Test file permissions
    static func testFilePermissions(at url: URL) throws -> FilePermissions {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let posixPermissions = attributes[.posixPermissions] as? Int ?? 0
        
        return FilePermissions(
            readable: (posixPermissions & 0o400) != 0,
            writable: (posixPermissions & 0o200) != 0,
            executable: (posixPermissions & 0o100) != 0
        )
    }
    
    struct FilePermissions {
        let readable: Bool
        let writable: Bool
        let executable: Bool
    }
    
    /// Make a file read-only
    static func makeReadOnly(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: url.path
        )
    }
    
    // MARK: - File Watching
    
    /// Monitor file system changes in a directory
    class DirectoryMonitor {
        private let url: URL
        private var source: DispatchSourceFileSystemObject?
        private var fileDescriptor: Int32 = -1
        var onChange: (() -> Void)?
        
        init(url: URL) {
            self.url = url
        }
        
        func start() throws {
            fileDescriptor = open(url.path, O_EVTONLY)
            guard fileDescriptor != -1 else {
                throw FileSystemError.cannotOpenDirectory
            }
            
            source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename],
                queue: .main
            )
            
            source?.setEventHandler { [weak self] in
                self?.onChange?()
            }
            
            source?.resume()
        }
        
        func stop() {
            source?.cancel()
            if fileDescriptor != -1 {
                close(fileDescriptor)
                fileDescriptor = -1
            }
        }
        
        deinit {
            stop()
        }
    }
    
    // MARK: - Atomic Operations
    
    /// Perform atomic file write
    static func atomicWrite(data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        
        try data.write(to: tempURL)
        try FileManager.default.moveItem(at: tempURL, to: url)
    }
    
    // MARK: - File Comparison
    
    /// Compare two files byte-by-byte
    static func filesAreIdentical(url1: URL, url2: URL) throws -> Bool {
        let data1 = try Data(contentsOf: url1)
        let data2 = try Data(contentsOf: url2)
        return data1 == data2
    }
    
    /// Get file size
    static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    // MARK: - Cleanup Verification
    
    /// Snapshot directory contents
    struct DirectorySnapshot {
        let files: Set<String>
        let directories: Set<String>
        
        static func capture(at url: URL) throws -> DirectorySnapshot {
            var files: Set<String> = []
            var directories: Set<String> = []
            
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            
            while let fileURL = enumerator?.nextObject() as? URL {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                
                if resourceValues.isDirectory == true {
                    directories.insert(relativePath)
                } else {
                    files.insert(relativePath)
                }
            }
            
            return DirectorySnapshot(files: files, directories: directories)
        }
        
        func compare(with other: DirectorySnapshot) -> SnapshotDiff {
            let addedFiles = other.files.subtracting(files)
            let removedFiles = files.subtracting(other.files)
            let addedDirectories = other.directories.subtracting(directories)
            let removedDirectories = directories.subtracting(other.directories)
            
            return SnapshotDiff(
                addedFiles: addedFiles,
                removedFiles: removedFiles,
                addedDirectories: addedDirectories,
                removedDirectories: removedDirectories
            )
        }
    }
    
    struct SnapshotDiff {
        let addedFiles: Set<String>
        let removedFiles: Set<String>
        let addedDirectories: Set<String>
        let removedDirectories: Set<String>
        
        var hasChanges: Bool {
            !addedFiles.isEmpty || !removedFiles.isEmpty ||
            !addedDirectories.isEmpty || !removedDirectories.isEmpty
        }
    }
}

// MARK: - Errors

enum FileSystemError: Error {
    case cannotDetermineSpace
    case cannotOpenDirectory
    case permissionDenied
    case fileNotFound
}
