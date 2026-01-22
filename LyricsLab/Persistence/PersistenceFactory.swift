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
        let configuration: ModelConfiguration
        if iCloudSyncEnabled {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
