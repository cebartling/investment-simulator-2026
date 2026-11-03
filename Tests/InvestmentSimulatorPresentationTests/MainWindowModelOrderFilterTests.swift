import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

/// Hiding expired and cancelled orders from the order rows (PIN-406).
extension MainWindowModelTests {
    @Test func `order rows hide expired and cancelled orders by default`() async throws {
        var now = fixedNow
        let model = try await makeModelWithEveryOrderStatus(clock: { now })
        now = fixedNow.addingTimeInterval(60)
        _ = try #require(model.cancelOrder(id: cancelledOrderID))

        let rows = model.limitOrderRows(at: now)

        #expect(!model.showsExpiredAndCancelledOrders)
        #expect(rows.map(\.id) == [filledOrderID, fixedOrderID])
        #expect(rows.map(\.status) == [.filled(sessionDate: "2026-10-28"), .open])
    }

    @Test func `order rows show expired and cancelled orders when asked`() async throws {
        var now = fixedNow
        let model = try await makeModelWithEveryOrderStatus(clock: { now })
        now = fixedNow.addingTimeInterval(60)
        _ = try #require(model.cancelOrder(id: cancelledOrderID))

        model.showsExpiredAndCancelledOrders = true
        let rows = model.limitOrderRows(at: now)

        #expect(rows.map(\.id) == [expiredOrderID, filledOrderID, fixedOrderID, cancelledOrderID])
        #expect(rows.map(\.status) == [.expired, .filled(sessionDate: "2026-10-28"), .open, .cancelled])
    }

    @Test func `an open order leaves the default rows once it expires`() async throws {
        let open = try makeOrder(shares: 2)
        let model = try await makeModelWithPurchase(orders: [open])

        #expect(model.limitOrderRows(at: fixedNow).map(\.id) == [open.id])
        #expect(model.limitOrderRows(at: open.expiresAt).isEmpty)
    }

    @Test func `a cancelled buy order leaves the default rows`() async throws {
        var now = fixedNow
        let buy = try makeBuyOrder(shares: 4)
        let model = try await makeModelWithBuyOrders([buy], clock: { now })
        now = fixedNow.addingTimeInterval(60)

        _ = try #require(model.cancelOrder(id: buy.id))

        #expect(model.limitOrderRows(at: now).isEmpty)
        #expect(model.experiment.buyLimitOrders.map(\.id) == [buy.id])
    }

    /// A model whose sell orders, once the last is cancelled, are expired,
    /// filled, open (`fixedOrderID`) and cancelled, placed in that order.
    private func makeModelWithEveryOrderStatus(clock: @escaping () -> Date) async throws -> MainWindowModel {
        let expired = try makeOrder(
            id: expiredOrderID,
            shares: 1,
            placedAt: fixedNow.addingTimeInterval(-100 * 86400),
        )
        let filled = try makeOrder(id: filledOrderID, shares: 1, placedAt: fixedNow.addingTimeInterval(-2))
            .filled(on: "2026-10-28")
        let open = try makeOrder(shares: 1, placedAt: fixedNow.addingTimeInterval(-1))
        let cancelled = try makeOrder(id: cancelledOrderID, shares: 1)
        return try await makeModelWithPurchase(orders: [expired, filled, open, cancelled], clock: clock)
    }
}

private let expiredOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
private let filledOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
private let cancelledOrderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!
