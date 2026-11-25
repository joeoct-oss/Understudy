//
//  Macros.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// Writes a test double: one ``Spy`` or ``ThrowingSpy`` per requirement, and the code that calls it.
///
/// On a class, mark each function ``Spied()`` and give it no body, and each property
/// ``SpiedProperty()`` with a type and nothing else; the macro writes the code and the spy. The shipped code stays untouched, and the compiler checks every signature against the
/// protocol:
///
/// ```swift
/// @Understudy
/// final class SpyCatalog: Catalog {
///     @Spied func product(id: Int) -> Product?
/// }
///
/// catalog.productSpy.willReturn(.apple)
/// #expect(catalog.productSpy.calls == expectedIDs)
/// ```
///
/// On a protocol you own, it writes a class named after the protocol with `Spy` added, such as
/// `CatalogSpy`, next to it. The protocol's target then depends on Understudy. A protocol that
/// inherits another, other than `Sendable` or `AnyObject`, needs the class form.
///
/// Each spy is named after its requirement with `Spy` added, such as `productSpy`; overloads add
/// their argument labels, such as `removeIdSpy` and `removeNamedSpy`. A requirement with several
/// parameters records a labelled tuple of them. A requirement that throws gets a ``ThrowingSpy``.
/// The double's initializer asks for the answer of every requirement that returns something other
/// than `Void` or an optional, and the value of every property that isn't optional, so a double
/// can't be called with nothing scripted. A property gets a ``PropertySpy``. An async requirement
/// goes through ``Spy/respond(to:isolation:)``, so the test can hold the call. Subscripts, static
/// and generic requirements are written by hand.
@attached(member, names: arbitrary)
@attached(peer, names: suffixed(Spy))
public macro Understudy() = #externalMacro(module: "UnderstudyMacros", type: "UnderstudyMacro")

/// Marks a function of an ``Understudy()`` class that the macro writes. Give it no body.
@attached(body)
public macro Spied() = #externalMacro(module: "UnderstudyMacros", type: "SpiedMacro")

/// Marks a property of an ``Understudy()`` class that the macro writes. Declare it as a `var` with
/// a type and nothing else; the macro writes its getter and setter, and the double's initializer
/// takes its value unless it is optional.
@attached(accessor)
public macro SpiedProperty() = #externalMacro(module: "UnderstudyMacros", type: "SpiedPropertyMacro")
