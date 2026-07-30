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

    func testPaidThirdWorkbenchRunsResearchAndTwoCrafts() throws {
        let now = Date(timeIntervalSince1970: 12_000)
        var state = IdleOperationsState.newGame(now: now)
        state.workbenchSlots = 3
        _ = try IdleOperationsEngine.start(.research, now: now, identifier: "research", state: &state)
        _ = try IdleOperationsEngine.start(.craft, now: now, identifier: "craft-1", state: &state)
        _ = try IdleOperationsEngine.start(.craft, now: now, identifier: "craft-2", state: &state)

        XCTAssertEqual(state.active.filter { $0.kind == .research || $0.kind == .craft }.count, 3)
        XCTAssertThrowsError(
            try IdleOperationsEngine.start(.craft, now: now, identifier: "craft-3", state: &state)
        ) {
            XCTAssertEqual($0 as? IdleOperationError, .slotFull)
        }
    }

    func testCraftSpeedAppliesOnlyWhenANewOperationStarts() throws {
        let now = Date(timeIntervalSince1970: 13_000)
        var normalState = IdleOperationsState.newGame(now: now)
        let existing = try IdleOperationsEngine.start(
            .craft,
            now: now,
            identifier: "existing",
            craftSpeedMultiplier: 1,
            state: &normalState
        )
        let existingCompletion = existing.completesAt

        var paidState = IdleOperationsState.newGame(now: now)
        let paid = try IdleOperationsEngine.start(
            .craft,
            now: now,
            identifier: "paid",
            craftSpeedMultiplier: 1.10,
            state: &paidState
        )

        XCTAssertEqual(existing.completesAt.timeIntervalSince(now), 15 * 60)
        XCTAssertEqual(paid.completesAt.timeIntervalSince(now), 15 * 60 / 1.10, accuracy: 0.001)
        XCTAssertEqual(normalState.active[0].completesAt, existingCompletion, "Later entitlement changes must not rewrite running work")
    }

    func testDailyInstantFinishIsOneUsePerUTCDayAndIdempotent() throws {
        let dayOne = Date(timeIntervalSince1970: 86_400 * 10)
        var state = IdleOperationsState.newGame(now: dayOne)
        var ticket = DailyInstantFinishState.empty
        let first = try IdleOperationsEngine.start(.craft, now: dayOne, identifier: "first", state: &state)

        try IdleOperationsEngine.finishWithDailyTicket(
            id: first.id,
            now: dayOne,
            entitled: true,
            ticket: &ticket,
            state: &state
        )
        XCTAssertEqual(ticket.remainingUses(on: dayOne, entitled: true), 0)
        XCTAssertEqual(ticket.consumedOperationIDs, ["first"])
        XCTAssertThrowsError(
            try IdleOperationsEngine.finishWithDailyTicket(
                id: first.id,
                now: dayOne,
                entitled: true,
                ticket: &ticket,
                state: &state
            )
        ) {
            XCTAssertEqual($0 as? IdleOperationError, .notComplete)
        }
        XCTAssertEqual(ticket.consumedOperationIDs, ["first"])
        _ = try IdleOperationsEngine.claim(id: first.id, now: dayOne, state: &state)

        let second = try IdleOperationsEngine.start(.craft, now: dayOne, identifier: "second", state: &state)
        XCTAssertThrowsError(
            try IdleOperationsEngine.finishWithDailyTicket(
                id: second.id,
                now: dayOne,
                entitled: true,
                ticket: &ticket,
                state: &state
            )
        ) {
            XCTAssertEqual($0 as? IdleOperationError, .dailyTicketAlreadyUsed)
        }

        let dayTwo = dayOne.addingTimeInterval(86_400)
        _ = try IdleOperationsEngine.claim(id: second.id, now: dayTwo, state: &state)
        let third = try IdleOperationsEngine.start(.craft, now: dayTwo, identifier: "third", state: &state)
        try IdleOperationsEngine.finishWithDailyTicket(
            id: third.id,
            now: dayTwo,
            entitled: true,
            ticket: &ticket,
            state: &state
        )
        XCTAssertEqual(ticket.utcDayKey, DailyInstantFinishState.dayKey(for: dayTwo))
        XCTAssertEqual(ticket.consumedOperationIDs, ["third"])
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
        XCTAssertEqual(decoded.dailyInstantFinish, .empty)
        XCTAssertEqual(decoded.equippedBoraUniform, .base)
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
