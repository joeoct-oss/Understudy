//
//  ProtocolSpyTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// The spy `@GenerateSpies` writes next to a protocol with associated types, which is generic, and
/// next to a protocol that inherits others, which answers the parents' requirements through their
/// spies.
@Suite("Protocol spies for associated types and inherited protocols")
struct ProtocolSpyTests {
    @Test("A protocol with an associated type gets a generic spy that answers and records that type")
    func associatedTypeGivesAGenericSpy() {
        let repository = RepositorySpy<Product>()
        repository.itemSpy.willReturn(Product(name: "lamp"))

        let item = repository.item(id: 7)
        repository.save(Product(name: "desk"))

        let expectedIDs = [7]
        let expectedSaves = [Product(name: "desk")]
        #expect(item == Product(name: "lamp"))
        #expect(repository.itemSpy.calls == expectedIDs)
        #expect(repository.saveSpy.calls == expectedSaves)
    }

    @Test("A call to a parent's requirement on the child's spy lands in the parent's spy")
    func childSpyForwardsToItsParentsSpy() {
        let base = BaseSpy(ping: 0)
        let child = ChildSpy(base: base)

        _ = child.ping()
        child.name = "ana"
        child.pong("hi")

        let expectedPongs = ["hi"]
        #expect(child.pingSpy.callCount == 1)
        #expect(base.pingSpy.callCount == 1)
        #expect(child.name == "ana")
        #expect(base.name == "ana")
        #expect(child.pongSpy.calls == expectedPongs)
    }

    @Test("A child of two parents answers with the parent spies its initializer was given, and records in them")
    func childSpyForwardsToEveryParent() {
        let child = ProfileSpy(base: BaseSpy(ping: 1), named: NamedSpy(title: "Dr"))

        let ping = child.ping()
        let title = child.title()
        child[2] = "row"

        #expect(ping == 1)
        #expect(title == "Dr")
        #expect(child.titleSpy.callCount == 1)
        #expect(child.subscriptSetSpy.lastCall?.newValue == "row")
    }

    @Test("A grandchild's spy reaches its grandparent's requirements through its parent's spy")
    func grandchildSpyForwardsToItsGrandparent() {
        let base = BaseSpy(ping: 5)
        let grandchild = GrandchildSpy(child: ChildSpy(base: base))

        let ping = grandchild.ping()
        grandchild.pong("hey")
        grandchild.wave()

        let expectedPongs = ["hey"]
        #expect(ping == 5)
        #expect(base.pingSpy.callCount == 1)
        #expect(grandchild.pongSpy.calls == expectedPongs)
        #expect(grandchild.waveSpy.callCount == 1)
    }

    @Test("A main-actor parent's requirement is answered on the main actor through the child's spy")
    @MainActor
    func mainActorParentForwards() {
        let child = DetailScreenSpy(screen: ScreenSpy())

        child.show("Home")
        child.close()

        let expectedShows = ["Home"]
        #expect(child.showSpy.calls == expectedShows)
        #expect(child.closeSpy.callCount == 1)
    }

    @Test("An actor protocol with an associated type gets an actor spy that records that type")
    func actorProtocolWithAssociatedTypeGetsAnActorSpy() async {
        let store = StoreSpy<String>()

        await store.save("receipt")

        let expectedSaves = ["receipt"]
        #expect(store.saveSpy.calls == expectedSaves)
    }

    @Test("A parent's static requirement is reached through the child's spy, in the parent's static spies")
    func parentStaticRequirementForwards() async throws {
        // A trait can't name a spy class written next to a protocol, because Swift doesn't look
        // into macro expansions from a macro's arguments, so the test asks the parent's spy for
        // fresh spies itself, as `.freshSpies(TickerSpy.self)` would.
        try await TickerSpy.withFreshSpies {
            TickerSpy.nowSpy.willReturn(42)

            let now = CountdownSpy.now()

            #expect(now == 42)
            #expect(CountdownSpy.nowSpy.callCount == 1)
            #expect(TickerSpy.nowSpy.callCount == 1)
        }
    }
}

/// A value a repository keeps.
///
/// Conformances:
/// - `Equatable`, so the repository's item type and the test can compare it.
private struct Product: Equatable {
    let name: String
}

/// Keeps items of a type each app picks.
@GenerateSpies
private protocol Repository {
    associatedtype Item: Equatable

    func item(id: Int) -> Item?
    func save(_ item: Item)
}

/// Keeps items of a type each app picks, inside an actor.
@GenerateSpies
private protocol Store: Actor {
    associatedtype Item

    func save(_ item: Item)
}

/// A parent protocol, with a function and a property.
@GenerateSpies
private protocol Base {
    var name: String { get set }

    func ping() -> Int
}

/// Inherits `Base`, and adds a requirement of its own.
@GenerateSpies
private protocol Child: Base {
    func pong(_ value: String)
}

/// A second parent, with a subscript.
@GenerateSpies
private protocol Named {
    subscript(index: Int) -> String { get set }

    func title() -> String
}

/// Inherits two parents, and adds nothing.
@GenerateSpies
private protocol Profile: Base, Named { }

/// Inherits a protocol that inherits another.
@GenerateSpies
private protocol Grandchild: Child {
    func wave()
}

/// A main-actor parent.
@GenerateSpies
@MainActor
private protocol Screen {
    func show(_ title: String)
}

/// Inherits a main-actor parent.
@GenerateSpies
@MainActor
private protocol DetailScreen: Screen {
    func close()
}

/// A parent with a static requirement.
@GenerateSpies
private protocol Ticker {
    static func now() -> Int
}

/// Inherits a parent with a static requirement.
@GenerateSpies
private protocol Countdown: Ticker {
    func start()
}
