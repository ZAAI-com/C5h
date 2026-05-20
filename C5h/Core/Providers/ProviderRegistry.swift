import Foundation
import C5hCore

@MainActor
final class ProviderRegistry {
    private(set) var adapters: [ProviderID: any ProviderAdapter]

    init(adapters: [any ProviderAdapter]) {
        self.adapters = Dictionary(adapters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func adapter(for id: ProviderID) throws -> any ProviderAdapter {
        guard let adapter = adapters[id] else {
            throw C5hError.providerNotConfigured(id.rawValue)
        }
        return adapter
    }

    func allAdapters() -> [any ProviderAdapter] {
        ProviderID.allCases.compactMap { adapters[$0] }
    }
}
