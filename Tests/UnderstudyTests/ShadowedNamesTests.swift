//
//  ShadowedNamesTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// The generated code names every type it uses with its module, so the test's own types with the
/// same names never take their place. The doubles sit inside `Shadowed`, which declares one of
/// each, so its names win there over Swift's and Understudy's.
@Suite("Shadowed names")
struct ShadowedNamesTests {
    @Test("A generated double builds and works next to types of its own named Spy, Void or TaskLocal")
    func doubleWorksWhenTheTestTargetShadowsTheNamesItUses() async throws {
        try await Shadowed.InventorySpy.withFreshSpies {
            try await Shadowed.SpyShelf.withFreshSpies {
                let inventory = Shadowed.InventorySpy(subscript: "shelf", count: 3, load: "lamp")
                let shelf = Shadowed.SpyShelf(label: "top")
                Shadowed.InventorySpy.regionSpy.willReturn("north")
                inventory.pickSpy.willReturn(5)
                let choices = [4, 5]

                inventory.owner = "ana"
                try inventory.restock("lamp")
                let loaded = try await inventory.load(id: 7)
                inventory[2] = "bin"
                shelf.height = 4
                let picked = inventory.pick(choices)

                let restocked = ["lamp"]
                #expect(inventory.count(of: "lamp") == 3)
                #expect(inventory.restockSpy.calls == restocked)
                #expect(loaded == "lamp")
                #expect(picked == 5)
                #expect(inventory.owner == "ana")
                #expect(inventory[2] == "shelf")
                #expect(inventory.subscriptSetSpy.callCount == 1)
                #expect(Shadowed.InventorySpy.region() == "north")
                #expect(shelf.label() == "top")
                #expect(shelf.height == 4)
                #expect(Shadowed.SpyShelf.size() == 0)
            }
        }
    }
}

/// The names the generated code uses, declared again, with the doubles that must not pick them up.
enum Shadowed {
    /// The error a double throws as a typed `throws`, which the generated body rethrows.
    ///
    /// Conformances:
    /// - `Error`, so the double can throw it.
    enum StockError: Error {
        case missing
    }

    /// Keeps stock: a protocol whose spy the macro writes next to it.
    @GenerateSpies
    protocol Inventory {
        var owner: String { get set }

        subscript(index: Int) -> String { get set }

        static func region() -> String

        func count(of item: String) -> Int
        func restock(_ item: String) throws
        func load(id: Int) async throws(StockError) -> String
        func pick<Item: Equatable>(_ items: [Item]) -> Item?
    }

    /// A shelf: a class whose spies the macro adds to it.
    @GenerateSpies
    final class SpyShelf {
        @SpiedProperty var height: Int

        @Spied static func size() -> Int

        @Spied func label() -> String
    }

    /// Shadows `Understudy.Spy`.
    struct Spy { }

    /// Shadows `Understudy.ThrowingSpy`.
    struct ThrowingSpy { }

    /// Shadows `Understudy.PropertySpy`.
    struct PropertySpy { }

    /// Shadows `Understudy.StaticSpies`.
    protocol StaticSpies { }

    /// Shadows Swift's `TaskLocal`.
    struct TaskLocal { }

    /// Shadows `Swift.Void`.
    struct Void { }

    /// Shadows `Swift.Set`.
    struct Set { }

    /// Shadows `Swift.AnyHashable`.
    struct AnyHashable { }

    /// Shadows `Swift.Sendable`.
    protocol Sendable { }

    /// Shadows `Swift.fatalError(_:)`. A generated body never calls it.
    static func fatalError(_ message: String) -> Never {
        Swift.fatalError("The shadowing fatalError was called: \(message)")
    }
}
