import Foundation

enum GameSaveStoreError: Error {
    case unsupportedSchema(Int)
}

final class GameSaveStore: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = base.appendingPathComponent("StarJunkyard", isDirectory: true)
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    var mainURL: URL { directory.appendingPathComponent("save-main.json") }
    var backupURL: URL { directory.appendingPathComponent("save-backup.json") }

    func load() -> GameSave? {
        for url in [mainURL, backupURL] {
            guard let data = try? Data(contentsOf: url),
                  let save = try? decode(data)
            else { continue }
            return save
        }
        return nil
    }

    func save(_ save: GameSave) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: mainURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: mainURL, to: backupURL)
        }
        try encode(save).write(to: mainURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func importCloudData(_ data: Data) throws -> GameSave {
        let save = try decodeCloudData(data)
        try self.save(save)
        return save
    }

    func decodeCloudData(_ data: Data) throws -> GameSave {
        try decode(data)
    }

    func exportCloudData(_ save: GameSave) throws -> Data {
        try encode(save)
    }

    private func encode(_ save: GameSave) throws -> Data {
        try encoder.encode(save)
    }

    private func decode(_ data: Data) throws -> GameSave {
        var save = try decoder.decode(GameSave.self, from: data)
        guard (1...GameSave.currentSchemaVersion).contains(save.schemaVersion) else {
            throw GameSaveStoreError.unsupportedSchema(save.schemaVersion)
        }
        if save.schemaVersion == 1 {
            save.schemaVersion = GameSave.currentSchemaVersion
            save.enemyHPs = save.enemyHP.map { [$0] }
            save.crewLevel = 1
        }
        return save
    }
}
