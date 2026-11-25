//
//  Sample.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// Writes `static func sample(...)` on a struct, so a test gets a complete value in one call and
/// names only the values it is about:
///
/// ```swift
/// @Sample
/// struct Product {
///     let id: UUID
///     let name: String
///     let price: Decimal
///     var stock: Int = 5
/// }
///
/// let free = Product.sample(price: 0)
/// ```
///
/// `sample(...)` has one parameter per property the memberwise initializer takes, each with a
/// default, and builds the value with that initializer. The defaults are `""`, `0`, `false`,
/// `nil`, empty collections, `Date(timeIntervalSince1970: 0)`, the all-zero `UUID` and
/// `https://example.com`. A property's own initial value is its default, and
/// ``SampleDefault(_:)`` sets another one. Any other type is asked for its own `.sample()`, so a
/// property whose type has `@Sample` too just works; for a type without one, the compiler stops at
/// that parameter, and ``SampleDefault(_:)`` gives it a value. A `let` that has its value,
/// a computed property and a static one are left out.
///
/// `sample(...)` is written inside `#if DEBUG`, so a release build carries none of it, and it is as
/// visible as the struct: a test that imports a module without `@testable` can call a public
/// struct's sample. The struct needs its memberwise initializer.
@attached(member, names: named(sample))
public macro Sample() = #externalMacro(module: "UnderstudySamplesMacros", type: "SampleMacro")

/// Sets the default of one property's `sample(...)` parameter, in a ``Sample()`` struct:
///
/// ```swift
/// @SampleDefault("EGP") let currency: String
/// @SampleDefault(Seller.sample(name: "Ana")) let seller: Seller
/// ```
///
/// Write the value's type in full, as in `Seller.sample(...)`, because the attribute can't see the
/// property's type.
@attached(peer)
public macro SampleDefault<Value>(_ value: Value) = #externalMacro(
    module: "UnderstudySamplesMacros",
    type: "SampleDefaultMacro"
)
