import XCTest
@testable import StarJunkyard

final class IdleOperationsTests: XCTestCase {
    func testWorkbenchSlotsAndDifferentOperationKinds() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var state = IdleOperationsState.newGame(now: now)
        let research = try IdleOperationsEngine.start(.research, now: now, identifier: "research", state: &state)
        let craft = try IdleOperationsEngine.start(.craft, now: now, identifier: "craft", state: &state)
        let expedition = try IdleOperationsEngine.start(.expedition, now: now, identifier: "expedition", state: &state)

        XCTAssertEqual(state.active.count, 3)
        XCTAssertEqual(research.completesAt.timeIntervalSince(now), 5 * 60)
        XCTAssertEqual(craft.completesAt.timeIntervalSince(now), 15 * 60)
        XCTAssertEqual(expedition.completesAt.timeIntervalSince(now), 30 * 60)
        XCTAssertThrowsError(try IdleOperationsEngine.start(.research, now: now, state: &state)) {
            XCTAssertEqual($0 as? IdleOperationError, .alreadyRunning)
        }
    }

    func testSaveRoundTripPreservesRunningOperationAndClaimState() throws {
        let now = Date(timeIntervalSince1970: 15_000)
        var state = IdleOperationsState.newGame(now: now)
        _ = try IdleOperationsEngine.start(.expedition, now: now, identifier: "saved-expedition", state: &state)

        var save = GameSave.newGame(now: now)
        save.idleOperations = state
        let decoded = try JSONDecoder().decode(GameSave.self, from: JSONEncoder().encode(save))

        XCTAssertEqual(decoded.idleOperations.active.map(\.id), ["saved-expedition"])
        XCTAssertEqual(decoded.idleOperations.active.first?.completesAt, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(decoded.idleOperations.circuits, 0)
    }

    func testFreeFinishOnlyWithinLastThreeMinutesAndClaimIsIdempotent() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        var state = IdleOperationsState.newGame(now: now)
        let operation = try IdleOperationsEngine.start(.craft, now: now, identifier: "craft", state: &state)
        XCTAssertThrowsError(try IdleOperationsEngine.finishFree(id: operation.id, now: now, state: &state)) {
            XCTAssertEqual($0 as? IdleOperationError, .freeFinishUnavailable)
        }

        let nearCompletion = operation.completesAt.addingTimeInterval(-120)
        try IdleOperationsEngine.finishFree(id: operation.id, now: nearCompletion, state: &state)
        let reward = try IdleOperationsEngine.claim(id: operation.id, now: nearCompletion, state: &state)
        XCTAssertEqual(reward.alloy, 1)
        XCTAssertEqual(state.alloy, 1)
        XCTAssertThrowsError(try IdleOperationsEngine.claim(id: operation.id, now: nearCompletion, state: &state)) {
            XCTAssertEqual($0 as? IdleOperationError, .notComplete)
        }
    }

    func testExpeditionRewardAndResearchPersistWithoutDuplication() throws {
        let now = Date(timeIntervalSince1970: 30_000)
        var state = IdleOperationsState.newGame(now: now)
        let expedition = try IdleOperationsEngine.start(.expedition, now: now, identifier: "expedition", state: &state)
        let expeditionReward = try IdleOperationsEngine.claim(
            id: expedition.id,
            now: expedition.completesAt,
            state: &state
        )
        XCTAssertEqual(expeditionReward.credits, 120)
        XCTAssertEqual(expeditionReward.parts, 42)
        XCTAssertEqual(state.circuits, 3)

        let research = try IdleOperationsEngine.start(.research, now: expedition.completesAt, identifier: "research", state: &state)
        _ = try IdleOperationsEngine.claim(id: research.id, now: research.completesAt, state: &state)
        XCTAssertEqual(state.completedResearchIDs, ["reuse_protocol_1"])
    }

    func testClockRollbackBlocksCompletionUntilObservedTimeRecovers() throws {
        let now = Date(timeIntervalSince1970: 40_000)
        var state = IdleOperationsState.newGame(now: now)
        _ = try IdleOperationsEngine.start(.research, now: now, identifier: "research", state: &state)
        IdleOperationsEngine.observe(now: now.addingTimeInterval(-301), state: &state)
        XCTAssertTrue(state.clockSuspect)
        XCTAssertThrowsError(
            try IdleOperationsEngine.claim(id: "research", now: now.addingTimeInterval(-301), state: &state)
        )
        IdleOperationsEngine.observe(now: now.addingTimeInterval(601), state: &state)
        XCTAssertFalse(state.clockSuspect)
        XCTAssertNoThrow(try IdleOperationsEngine.claim(id: "research", now: now.addingTimeInterval(601), state: &state))
    }

    func testNotificationPermissionThresholdSkipsShortResearch() {
        XCTAssertLessThan(
            IdleOperationsRules.template(for: .research).duration,
            IdleOperationsRules.notificationPermissionThreshold
        )
        XCTAssertGreaterThanOrEqual(
            IdleOperationsRules.template(for: .craft).duration,
            IdleOperationsRules.notificationPermissionThreshold
        )
    }
}
