//
//  SampleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation
import Testing
import UnderstudySamples

/// What a test gets from `@Sample`: a complete value in one call, where it names only the values
/// it is about.
@Suite("Samples")
struct SampleTests {
    @Test
    func sampleFillsEveryStoredPropertyWithItsDefault() {
        let defaults = Defaults.sample()

        let noTags: [String] = []
        let noPrices: [String: Decimal] = [:]
        let noSizes: Set<Int> = []
        #expect(defaults.name == "")
        #expect(defaults.count == 0)
        #expect(defaults.ratio == 0)
        #expect(defaults.price == 0)
        #expect(defaults.isActive == false)
        #expect(defaults.note == nil)
        #expect(defaults.tags == noTags)
        #expect(defaults.prices == noPrices)
        #expect(defaults.sizes == noSizes)
        #expect(defaults.createdAt == Date(timeIntervalSince1970: 0))
        #expect(defaults.id == UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(defaults.link == URL(string: "https://example.com"))
    }

    @Test
    func sampleOverridesOnlyTheGivenProperties() {
        let free = Product.sample(price: 0, tags: ["home"])

        let expected = Product(
            id: Product.sample().id,
            name: "",
            price: 0,
            tags: ["home"],
            stock: 5,
            currency: "EGP",
            seller: Seller.sample()
        )
        #expect(free == expected)
    }

    @Test
    func nestedSampleTypesUseTheirOwnSample() {
        let product = Product.sample()

        #expect(product.seller == Seller.sample())
    }

    @Test
    func aPropertysInitialValueIsItsDefault() {
        let product = Product.sample()

        #expect(product.stock == 5)
    }

    @Test
    func sampleDefaultSetsThePropertysDefault() {
        let product = Product.sample()

        #expect(product.currency == "EGP")
        #expect(product.seller.rating == 4.5)
    }

    @Test
    func letWithAValueIsNotAParameter() {
        let product = Product.sample(name: "Lamp")

        #expect(product.kind == "physical")
        #expect(product.name == "Lamp")
    }

    @Test
    func computedStaticAndObservedPropertiesAreHandledLikeTheMemberwiseInitializer() {
        let counter = Counter.sample(value: 3)

        #expect(counter.value == 3)
        #expect(counter.doubled == 6)
        #expect(Counter.limit == 10)
    }
}

/// A struct with one stored property of each type that has a fixed default.
@Sample
struct Defaults {
    let name: String
    let count: Int
    let ratio: Double
    let price: Decimal
    let isActive: Bool
    let note: String?
    let tags: [String]
    let prices: [String: Decimal]
    let sizes: Set<Int>
    let createdAt: Date
    let id: UUID
    let link: URL
}

/// A struct whose sample a product's sample uses, with a default of its own.
///
/// Conformances:
/// - `Equatable`, so a test can compare a product's seller with a seller's sample.
@Sample
struct Seller: Equatable {
    let name: String
    @SampleDefault(4.5) let rating: Double
}

/// A struct with a property of each kind `@Sample` treats on its own.
///
/// Conformances:
/// - `Equatable`, so a test can compare a whole sample with the value it expects.
@Sample
struct Product: Equatable {
    let id: UUID
    let name: String
    let price: Decimal
    let tags: [String]
    var stock: Int = 5
    @SampleDefault("EGP") let currency: String
    let seller: Seller
    let kind = "physical"

    var isFree: Bool {
        price == 0
    }
}

/// A struct with the properties its memberwise initializer leaves out: a static one and a computed
/// one. An observed property is stored, so it stays.
@Sample
struct Counter {
    static let limit = 10

    var value: Int {
        didSet {
            print(value)
        }
    }

    var doubled: Int {
        value * 2
    }
}
