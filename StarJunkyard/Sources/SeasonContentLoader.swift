import Foundation

enum SeasonContentLoader {
    static func loadCatalog(bundle: Bundle = .main) -> SeasonCatalog {
        SeasonCatalog(
            current: load(named: "season-current", bundle: bundle),
            next: load(named: "season-next", bundle: bundle)
        )
    }

    static func decode(_ data: Data) throws -> SeasonDefinition {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SeasonDefinition.self, from: data)
    }

    private static func load(named name: String, bundle: Bundle) -> SeasonDefinition {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            preconditionFailure("\(name).json is missing from the app bundle")
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            preconditionFailure("Cannot decode \(name).json: \(error)")
        }
    }
}
