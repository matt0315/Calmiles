import Foundation
import SwiftData

enum CalmilesModelContainer {
    /// Prefer CloudKit when the app is signed with iCloud capability; otherwise local store.
    /// Toggle `preferCloudKit` after entitlements + container exist (see RELEASE.md).
    static func make(inMemory: Bool = false, preferCloudKit: Bool = false) -> ModelContainer {
        let schema = Schema([TripEntity.self])
        if inMemory {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [config])
        }
        if preferCloudKit {
            let cloud = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return container
            }
        }
        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
