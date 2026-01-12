import Foundation
import SwiftData
@testable import VoiceInk

/// Mock ModelContext for testing SwiftData operations
@available(macOS 14.0, *)
final class MockModelContext {
    
    // MARK: - Storage
    
    private var storage: [ObjectIdentifier: Any] = [:]
    private var deletedObjects: Set<ObjectIdentifier> = []
    
    // MARK: - Call Tracking
    
    private(set) var insertCallCount: Int = 0
    private(set) var deleteCallCount: Int = 0
    private(set) var saveCallCount: Int = 0
    private(set) var fetchCallCount: Int = 0
    
    var shouldThrowOnSave: Bool = false
    var shouldThrowOnFetch: Bool = false
    
    // MARK: - Mock Operations
    
    func insert<T: PersistentModel>(_ object: T) {
        insertCallCount += 1
        let id = ObjectIdentifier(object)
        storage[id] = object
    }
    
    func delete<T: PersistentModel>(_ object: T) {
        deleteCallCount += 1
        let id = ObjectIdentifier(object)
        deletedObjects.insert(id)
        storage.removeValue(forKey: id)
    }
    
    func save() throws {
        saveCallCount += 1
        
        if shouldThrowOnSave {
            throw MockModelContextError.saveFailed
        }
    }
    
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        fetchCallCount += 1
        
        if shouldThrowOnFetch {
            throw MockModelContextError.fetchFailed
        }
        
        // Return all objects of the requested type
        return storage.values.compactMap { $0 as? T }
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        storage.removeAll()
        deletedObjects.removeAll()
        insertCallCount = 0
        deleteCallCount = 0
        saveCallCount = 0
        fetchCallCount = 0
        shouldThrowOnSave = false
        shouldThrowOnFetch = false
    }
    
    func objectCount<T>(_ type: T.Type) -> Int {
        return storage.values.filter { $0 is T }.count
    }
    
    func wasDeleted<T: PersistentModel>(_ object: T) -> Bool {
        return deletedObjects.contains(ObjectIdentifier(object))
    }
    
    func allObjects<T>(ofType type: T.Type) -> [T] {
        return storage.values.compactMap { $0 as? T }
    }
}

/// Mock errors for ModelContext
enum MockModelContextError: Error, LocalizedError {
    case saveFailed
    case fetchFailed
    case insertFailed
    case deleteFailed
    
    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Mock save operation failed"
        case .fetchFailed:
            return "Mock fetch operation failed"
        case .insertFailed:
            return "Mock insert operation failed"
        case .deleteFailed:
            return "Mock delete operation failed"
        }
    }
}

/// Helper to create in-memory ModelContainer for tests
@available(macOS 14.0, *)
extension ModelContainer {
    static func createInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Transcription.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
