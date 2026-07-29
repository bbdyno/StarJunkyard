@preconcurrency import GameKit
import UIKit

enum CloudSaveError: LocalizedError, Sendable {
    case authenticationUnavailable
    case noCloudSave
    case invalidData
    case service(String)

    var errorDescription: String? {
        switch self {
        case .authenticationUnavailable: "Game Center에 연결할 수 없습니다. 로컬 저장은 안전합니다."
        case .noCloudSave: "Game Center에 저장된 게임이 없습니다."
        case .invalidData: "클라우드 저장 데이터를 읽을 수 없습니다."
        case .service(let message): message
        }
    }
}

private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !used else { return false }
        used = true
        return true
    }
}

@MainActor
final class GameCenterCloudSave {
    private weak var presenter: UIViewController?
    private let store: GameSaveStore

    init(presenter: UIViewController, store: GameSaveStore) {
        self.presenter = presenter
        self.store = store
    }

    func load(completion: @escaping @MainActor @Sendable (Result<GameSave, CloudSaveError>) -> Void) {
        authenticate { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                GKLocalPlayer.local.fetchSavedGames { games, error in
                    let gameBox = UncheckedSendableBox(games ?? [])
                    let errorMessage = error?.localizedDescription
                    DispatchQueue.main.async {
                        if let errorMessage { completion(.failure(.service(errorMessage))); return }
                        let matches = gameBox.value.filter { $0.name == GameSave.cloudSlotName }
                        guard !matches.isEmpty else { completion(.failure(CloudSaveError.noCloudSave)); return }
                        self.loadCandidates(UncheckedSendableBox(matches), index: 0, saves: [], completion: completion)
                    }
                }
            }
        }
    }

    func upload(_ save: GameSave, completion: @escaping @MainActor @Sendable (Result<GameSave, CloudSaveError>) -> Void) {
        authenticate { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                do {
                    let data = try self.store.exportCloudData(save)
                    GKLocalPlayer.local.saveGameData(data, withName: GameSave.cloudSlotName) { _, error in
                        let errorMessage = error?.localizedDescription
                        DispatchQueue.main.async {
                            if let errorMessage { completion(.failure(.service(errorMessage))) }
                            else { completion(.success(save)) }
                        }
                    }
                } catch {
                    completion(.failure(.service(error.localizedDescription)))
                }
            }
        }
    }

    private func authenticate(completion: @escaping @MainActor @Sendable (Result<Void, CloudSaveError>) -> Void) {
        if GKLocalPlayer.local.isAuthenticated {
            completion(.success(()))
            return
        }
        let gate = CompletionGate()
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            let viewControllerBox = UncheckedSendableBox(viewController)
            let errorMessage = error?.localizedDescription
            DispatchQueue.main.async {
                if let viewController = viewControllerBox.value {
                    self?.presenter?.present(viewController, animated: true)
                    return
                }
                guard gate.take() else { return }
                if let errorMessage { completion(.failure(.service(errorMessage))) }
                else if GKLocalPlayer.local.isAuthenticated { completion(.success(())) }
                else { completion(.failure(CloudSaveError.authenticationUnavailable)) }
            }
        }
    }

    private func loadCandidates(
        _ games: UncheckedSendableBox<[GKSavedGame]>,
        index: Int,
        saves: [GameSave],
        completion: @escaping @MainActor @Sendable (Result<GameSave, CloudSaveError>) -> Void
    ) {
        guard index < games.value.count else {
            guard let best = saves.max(by: {
                ($0.revision, $0.highestStage, $0.updatedAt) < ($1.revision, $1.highestStage, $1.updatedAt)
            }) else {
                completion(.failure(CloudSaveError.invalidData))
                return
            }
            completion(.success(best))
            return
        }
        let game = games.value[index]
        game.loadData { [weak self] data, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                var next = saves
                if let data, let decoded = try? self.store.decodeCloudData(data) {
                    next.append(decoded)
                }
                self.loadCandidates(games, index: index + 1, saves: next, completion: completion)
            }
        }
    }
}
