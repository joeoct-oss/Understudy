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
/// @GenerateSpies
/// final class SpyCatalog: Catalog {
///     @Spied func product(id: Int) -> Product?
/// }
///
/// catalog.productSpy.willReturn(.apple)
/// #expect(catalog.productSpy.calls == expectedIDs)
/// ```
///
/// On an actor, it writes the same members, with spies a test reads without `await`. On a
/// protocol you own, it writes a class named after the protocol with `Spy` added, such as
/// `CatalogSpy`, next to it, or an actor when the protocol inherits `Actor`. The protocol's target
/// then depends on Understudy. A protocol that inherits another, other than `Sendable`,
/// `AnyObject` or `Actor`, needs the class form.
///
/// Each spy is named after its requirement with `Spy` added, such as `productSpy`; overloads add
/// their argument labels, such as `removeIdSpy` and `removeNamedSpy`. A requirement with several
/// parameters records a labelled tuple of them. A requirement that throws gets a ``ThrowingSpy``;
/// with a typed `throws`, the body rethrows the scripted error as that type, and an error of
/// another type stops the test, naming the spy.
/// The double's initializer asks for the answer of every requirement that returns something other
/// than `Void` or an optional, and the value of every property that isn't optional, so a double
/// can't be called with nothing scripted. A property gets a ``PropertySpy``. An async requirement
/// goes through ``Spy/respond(to:isolation:)``, so the test can hold the call. A generic
/// parameter `T` is recorded as `any` of its constraints, and so is one inside an array, an
/// optional, a dictionary's value or a set: `[T]` as `[any Tag]`, `Set<T>` as `Set<AnyHashable>`.
/// A generic answer is cast back to the type the caller asks for. Subscripts and static
/// requirements are written by hand.
@attached(member, names: arbitrary)
@attached(peer, names: suffixed(Spy))
public macro GenerateSpies() = #externalMacro(module: "UnderstudyMacros", type: "GenerateSpiesMacro")

/// Marks a function of a ``GenerateSpies()`` class that the macro writes. Give it no body.
@attached(body)
public macro Spied() = #externalMacro(module: "UnderstudyMacros", type: "SpiedMacro")

/// Marks a property of a ``GenerateSpies()`` class that the macro writes. Declare it as a `var` with
/// a type, and a first value if you like; the macro writes its getter and setter. With a first
/// value, `@SpiedProperty var user: String = "ana"`, the spy starts with it; without one, the
/// double's initializer takes it unless it is optional. It works in a `Sendable` class and in an
/// actor, where ``Recorded`` can't.
@attached(accessor)
public macro SpiedProperty() = #externalMacro(module: "UnderstudyMacros", type: "SpiedPropertyMacro")
