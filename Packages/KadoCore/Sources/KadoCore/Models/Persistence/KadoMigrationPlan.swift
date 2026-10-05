import Foundation
import SwiftData

/// Migration plan for Kadō's persistent schema. Schemas are listed
/// oldest-to-newest; `stages` bridges each consecutive pair.
public enum KadoMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [KadoSchemaV1.self, KadoSchemaV2.self, KadoSchemaV3.self, KadoSchemaV4.self, KadoSchemaV5.self, KadoSchemaV6.self, KadoSchemaV7.self, KadoSchemaV8.self, KadoSchemaV9.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: KadoSchemaV1.self,
                toVersion: KadoSchemaV2.self
            ),
            .lightweight(
                fromVersion: KadoSchemaV2.self,
                toVersion: KadoSchemaV3.self
            ),
            .lightweight(
                fromVersion: KadoSchemaV3.self,
                toVersion: KadoSchemaV4.self
            ),
            .lightweight(
                fromVersion: KadoSchemaV4.self,
                toVersion: KadoSchemaV5.self
            ),
            .lightweight(
                fromVersion: KadoSchemaV5.self,
                toVersion: KadoSchemaV6.self
            ),
            .lightweight(fromVersion: KadoSchemaV6.self, toVersion: KadoSchemaV7.self),
            .lightweight(fromVersion: KadoSchemaV7.self, toVersion: KadoSchemaV8.self),
            .lightweight(fromVersion: KadoSchemaV8.self, toVersion: KadoSchemaV9.self)
        ]
    }
}
