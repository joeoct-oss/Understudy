//
//  FunctionDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// How a generated double of a function behaves once the compiler builds it: what it records,
/// what it answers, and what its initializer asks for.
@Suite("Generated doubles of functions")
struct FunctionDoubleTests {
    @Test("A generated requirement records its input and gives the standing answer")
    func requirementRecordsItsInputAndGivesTheStandingAnswer() {
        let catalog = SpyCatalog(product: "apple")

        let name = catalog.product(id: 7)

        let expectedIDs = [7]
        #expect(name == "apple")
        #expect(catalog.productSpy.calls == expectedIDs)
    }

    @Test("The initializer gives an obvious first answer when the test passes none")
    func initAsksOnlyForAnswersWithNoObviousDefault() {
        let shop = SpyShop()

        let name = shop.name()
        let stock = shop.stock()
        let price = shop.price()
        let open = shop.isOpen
        let tags = shop.tags()
        let prices = shop.prices()
        let codes = shop.codes()

        let noTags: [String] = []
        let noPrices: [String: Double] = [:]
        let noCodes: Set<Int> = []
        #expect(name == "")
        #expect(stock == 0)
        #expect(price == 0)
        #expect(!open)
        #expect(tags == noTags)
        #expect(prices == noPrices)
        #expect(codes == noCodes)
    }

    @Test("The initializer takes every answer a test passes")
    func initTakesEveryAnswerATestPasses() {
        let expectedTags = ["new"]
        let expectedPrices = ["tea": 2.5]
        let expectedCodes: Set = [7]
        let shop = SpyShop(
            isOpen: true,
            name: "Corner",
            stock: 9,
            price: 4.5,
            tags: expectedTags,
            prices: expectedPrices,
            codes: expectedCodes
        )

        #expect(shop.isOpen)
        #expect(shop.name() == "Corner")
        #expect(shop.stock() == 9)
        #expect(shop.price() == 4.5)
        #expect(shop.tags() == expectedTags)
        #expect(shop.prices() == expectedPrices)
        #expect(shop.codes() == expectedCodes)
    }

    @Test("Optional and Void answers need nothing at creation and still record calls")
    func optionalAndVoidAnswersNeedNothingAtCreation() {
        let catalog = SpyCatalog(product: "apple")

        let found = catalog.search(for: "pear", limit: 3)
        catalog.refresh()

        #expect(found == nil)
        #expect(catalog.searchSpy.lastCall?.query == "pear")
        #expect(catalog.searchSpy.lastCall?.limit == 3)
        #expect(catalog.refreshSpy.callCount == 1)
    }

    @Test("Overloads get spies named with their labels")
    func overloadsGetSpiesNamedWithTheirLabels() {
        let catalog = SpyCatalog(product: "apple")

        catalog.remove(id: 1)
        catalog.remove(named: "pear")

        let expectedIDs = [1]
        let expectedNames = ["pear"]
        #expect(catalog.removeIdSpy.calls == expectedIDs)
        #expect(catalog.removeNamedSpy.calls == expectedNames)
    }

    @Test("A closure answer is taken at creation and runs when called")
    func closureAnswerIsTakenAtCreation() {
        let ran = Spy<Void, Void>()
        let factory = SpyHandlerFactory(
            makeHandler: { ran() },
            makeSendableHandler: { ran() },
            makeWrappedHandler: { ran() }
        )

        factory.makeHandler()()
        factory.makeSendableHandler()()
        factory.makeWrappedHandler()()

        #expect(factory.makeHandlerSpy.callCount == 1)
        #expect(ran.callCount == 3)
    }

    @Test("Variadic and opaque parameters are recorded")
    func variadicAndOpaqueParametersAreRecorded() {
        let printer = SpyPrinter()

        printer.print("a", "b")
        printer.show(7)

        let expectedLines = [["a", "b"]]
        #expect(printer.printSpy.calls == expectedLines)
        #expect(printer.showSpy.lastCall as? Int == 7)
    }
}

/// A product catalog, as an app's feature would take it.
private protocol Catalog {
    func product(id: Int) -> String
    func search(for query: String, limit: Int) -> String?
    func refresh()
    func remove(id: Int)
    func remove(named name: String)
}

/// A catalog whose every requirement the macro writes.
///
/// Conformances:
/// - `Catalog`, so a test can pass it where a catalog is expected.
@GenerateSpies
private final class SpyCatalog: Catalog {
    @Spied func product(id: Int) -> String
    @Spied func search(for query: String, limit: Int) -> String?
    @Spied func refresh()
    @Spied func remove(id: Int)
    @Spied func remove(named name: String)
}

/// A shop whose every answer has an obvious first value.
///
/// Requirements:
/// - `AnyObject`, because a shop is one shared object whose `isOpen` a feature changes in place.
private protocol Shop: AnyObject {
    var isOpen: Bool { get set }
    func name() -> String
    func stock() -> Int
    func price() -> Double
    func tags() -> [String]
    func prices() -> [String: Double]
    func codes() -> Set<Int>
}

/// A shop the test makes with no arguments, or with only the answers it cares about.
///
/// Conformances:
/// - `Shop`, so a test can pass it where a shop is expected.
@GenerateSpies
private final class SpyShop: Shop {
    @SpiedProperty var isOpen: Bool
    @Spied func name() -> String
    @Spied func stock() -> Int
    @Spied func price() -> Double
    @Spied func tags() -> [String]
    @Spied func prices() -> [String: Double]
    @Spied func codes() -> Set<Int>
}

/// Prints lines and shows values.
///
/// Constraints:
/// - `show` takes `some Equatable`, so the spy has an opaque parameter to record.
private protocol Printer {
    func print(_ lines: String...)
    func show(_ value: some Equatable)
}

/// A printer that keeps what it was given.
///
/// Conformances:
/// - `Printer`, so a test can pass it where a printer is expected.
///
/// Constraints:
/// - `show` takes `some Equatable`, as `Printer` declares it.
@GenerateSpies
private final class SpyPrinter: Printer {
    @Spied func print(_ lines: String...)
    @Spied func show(_ value: some Equatable)
}

/// Makes the handler a screen runs when it is tapped.
private protocol HandlerFactory {
    func makeHandler() -> () -> Void
    func makeSendableHandler() -> @Sendable () -> Void
    func makeWrappedHandler() -> (() -> Void)
}

/// A handler factory that gives the closure the test chose.
///
/// Conformances:
/// - `HandlerFactory`, so a test can pass it where a factory is expected.
@GenerateSpies
private final class SpyHandlerFactory: HandlerFactory {
    @Spied func makeHandler() -> () -> Void
    @Spied func makeSendableHandler() -> @Sendable () -> Void
    @Spied func makeWrappedHandler() -> (() -> Void)
}
