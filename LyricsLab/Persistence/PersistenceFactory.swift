import Foundation
import SwiftData

enum PersistenceFactory {
    static func makeContainer(iCloudSyncEnabled: Bool) throws -> ModelContainer {
        let schema = Schema([
            Composition.self,
        ])

        // When iCloud is enabled, SwiftData will sync automatically if the project
        // has the CloudKit capability configured.
        //
        // When iCloud is disabled, we explicitly opt out of CloudKit syncing.
        if !iCloudSyncEnabled {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        // CloudKit-backed SwiftData can fail at runtime (capability/entitlements,
        // iCloud account state, transient CloudKit errors). Do not crash the app
        // on launch; fall back to a local-only store.
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
}
