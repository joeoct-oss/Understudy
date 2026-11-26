//
//  GenericDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// How a generated double of a generic function behaves once the compiler builds it.
@Suite("Generated doubles of generic functions")
struct GenericDoubleTests {
    @Test("Generic methods record their inputs and answer with the type the caller asks for")
    func genericMethodsRecordTheirInputsAndAnswerAsTheCallerAsks() async throws {
        let cache = SpyCache(load: 7)
        cache.valueSpy.willReturn("cached")

        cache.store(42, for: "answer")
        let text: String? = cache.value(for: "name")
        let missing: Int? = cache.missing(for: "none")
        let number: Int = try await cache.load("count")

        #expect(cache.storeSpy.lastCall?.value as? Int == 42)
        #expect(cache.storeSpy.lastCall?.key == "answer")
        #expect(text == "cached")
        #expect(missing == nil)
        #expect(number == 7)
    }

    @Test("A generic parameter inside an array or optional is recorded")
    func genericArrayParameterIsRecorded() {
        let noItems: [Int] = []
        let noLookup: [String: Int] = [:]
        let noUnique: Set<Int> = []
        let bag = SpyBag(all: noItems, lookup: noLookup, unique: noUnique)

        let expectedNumbers = [1, 2]
        let expectedLetters = ["a"]
        bag.put(expectedNumbers, first: nil)
        bag.put(expectedLetters, first: "b")

        #expect(bag.putSpy.calls.first?.items as? [Int] == expectedNumbers)
        #expect(bag.putSpy.lastCall?.items as? [String] == expectedLetters)
        #expect(bag.putSpy.lastCall?.first as? String == "b")
    }

    @Test("A generic answer inside a collection comes back as the caller's type")
    func genericArrayAnswerComesBackTyped() {
        let expectedItems = [3]
        let expectedFound = ["a": 1]
        let expectedUnique: Set = [5]
        let expectedShelved = ["x"]
        let asked = ["b": 2]
        let askedUnique: Set = [5, 6]
        let bag = SpyBag(all: expectedItems, lookup: expectedFound, unique: expectedUnique)
        let protocolBag = ShelfSpy(all: expectedShelved)

        let items: [Int] = bag.all()
        let found: [String: Int] = bag.lookup(asked)
        let unique: Set<Int> = bag.unique(askedUnique)
        let shelved: [String] = protocolBag.all()

        #expect(items == expectedItems)
        #expect(found == expectedFound)
        #expect(unique == expectedUnique)
        #expect(shelved == expectedShelved)
        #expect(bag.lookupSpy.lastCall?["b"] as? Int == 2)
        let recordedUnique: Set<AnyHashable> = [5, 6]
        #expect(bag.uniqueSpy.lastCall == recordedUnique)
    }

    @Test("A protocol's generic method gets a spy that records and answers")
    func protocolGenericMethodGetsASpy() {
        let reader = ReaderSpy(read: 3.5)

        let value: Double = reader.read("ratio")

        let expectedKeys = ["ratio"]
        #expect(reader.readSpy.calls == expectedKeys)
        #expect(value == 3.5)
    }
}

/// Keeps values of any type under keys.
///
/// Constraints:
/// - `store` needs `Codable` and `value` needs `Decodable`, as a cache that saves to disk would.
/// - `load` needs `Sendable`, because its answer crosses from the cache's task to the caller's.
private protocol Cache {
    func store<Value: Codable>(_ value: Value, for key: String)
    func value<Value: Decodable>(for key: String) -> Value?
    func missing<Value>(for key: String) -> Value?
    func load<Value: Sendable>(_ key: String) async throws -> Value
}

/// A cache whose answers the test chose, whatever type the caller asks for.
///
/// Conformances:
/// - `Cache`, so a test can pass it where a cache is expected.
///
/// Constraints:
/// - Each method keeps the constraint `Cache` declares for it, so the spy's signatures match.
@GenerateSpies
private final class SpyCache: Cache {
    @Spied func store<Value: Codable>(_ value: Value, for key: String)
    @Spied func value<Value: Decodable>(for key: String) -> Value?
    @Spied func missing<Value>(for key: String) -> Value?
    @Spied func load<Value: Sendable>(_ key: String) async throws -> Value
}

/// Holds items of any type, in arrays, dictionaries and sets.
///
/// Constraints:
/// - `all` needs `Codable`, as a bag read from disk would.
/// - `unique` needs `Hashable`, because its items go in a `Set`.
private protocol Bag {
    func put<Item>(_ items: [Item], first: Item?)
    func all<Item: Codable>() -> [Item]
    func lookup<Item>(_ map: [String: Item]) -> [String: Item]
    func unique<Item: Hashable>(_ items: Set<Item>) -> Set<Item>
}

/// A bag whose answers the test chose, whatever item type the caller asks for.
///
/// Conformances:
/// - `Bag`, so a test can pass it where a bag is expected.
///
/// Constraints:
/// - Each method keeps the constraint `Bag` declares for it, so the spy's signatures match.
@GenerateSpies
private final class SpyBag: Bag {
    @Spied func put<Item>(_ items: [Item], first: Item?)
    @Spied func all<Item: Codable>() -> [Item]
    @Spied func lookup<Item>(_ map: [String: Item]) -> [String: Item]
    @Spied func unique<Item: Hashable>(_ items: Set<Item>) -> Set<Item>
}

/// Lists the items on a shelf, of any type.
///
/// Constraints:
/// - `all` needs `Codable`, as a shelf read from disk would.
@GenerateSpies
private protocol Shelf {
    func all<Item: Codable>() -> [Item]
}

/// Reads settings of any type.
///
/// Constraints:
/// - `read` needs `Decodable`, because settings are decoded from storage.
@GenerateSpies
private protocol Reader {
    func read<Value: Decodable>(_ key: String) -> Value
}
