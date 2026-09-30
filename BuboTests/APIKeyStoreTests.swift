import Foundation
import Testing
@testable import Bubo

/// Runs against the real data protection keychain, each test in its own service.
struct APIKeyStoreTests {
    let store = APIKeyStore(service: "com.mgiuditta.bubo.tests.\(UUID().uuidString)")

    @Test func emptyStoreHasNoKey() async throws {
        #expect(try await store.key() == nil)
        #expect(try await store.containsKey() == false)
    }

    @Test func savedKeyIsReadBack() async throws {
        try await store.save("sk-ant-first")
        #expect(try await store.key() == "sk-ant-first")
        #expect(try await store.containsKey())
        try await store.delete()
    }

    @Test func savingAgainOverwrites() async throws {
        try await store.save("sk-ant-first")
        try await store.save("sk-ant-second")
        #expect(try await store.key() == "sk-ant-second")
        try await store.delete()
    }

    @Test func deleteRemovesTheKeyAndIsIdempotent() async throws {
        try await store.save("sk-ant-first")
        try await store.delete()
        #expect(try await store.containsKey() == false)
        try await store.delete()
    }
}
