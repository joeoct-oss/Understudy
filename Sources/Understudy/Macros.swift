//
//  Macros.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// Writes a test double: one ``Spy`` or ``ThrowingSpy`` per requirement, and the code that calls
/// it.
///
/// On a class, mark each function ``Spied()`` and give it no body, and each property
/// ``SpiedProperty()`` with a type and nothing else; the macro writes the code and the spy. The
/// shipped code stays untouched, and the compiler checks every signature against the protocol:
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
/// then depends on Understudy. A protocol with associated types gets a generic spy, one generic
/// parameter per associated type with its constraints: `RepositorySpy<Product>`. A protocol that
/// inherits another protocol with `@GenerateSpies` gets a spy that stores the parent's spy, taken
/// by its initializer, `ChildSpy(base: BaseSpy())`, and answers the parent's requirements
/// through it, with the parent's spies read on the child's: `child.pingSpy`. For that, the macro
/// also writes `<Name>SpyForwarding` next to every protocol.
///
/// Each spy is named after its requirement with `Spy` added, such as `productSpy`; overloads add
/// their argument labels, such as `removeIdSpy` and `removeNamedSpy`. A requirement with several
/// parameters records a labelled tuple of them. A requirement that throws gets a ``ThrowingSpy``;
/// with a typed `throws`, the body rethrows the scripted error as that type, and an error of
/// another type stops the test, naming the spy.
/// The double's initializer takes the first answer of every requirement and property, so a double
/// can't be called with nothing scripted. `Void` and optionals answer `()` and `nil`; a `String`,
/// a number, a `Bool` and an array, dictionary or set default to `""`, `0`, `false` and empty;
/// any other type is a required argument. A property gets a ``PropertySpy``. An async requirement
/// goes through ``Spy/respond(to:isolation:)``, so the test can hold the call. A generic
/// parameter `T` is recorded as `any` of its constraints, and so is one inside an array, an
/// optional, a dictionary's value or a set: `[T]` as `[any Tag]`, `Set<T>` as `Set<AnyHashable>`.
/// A generic answer is cast back to the type the caller asks for. A subscript gets a spy for its
/// gets and one for its sets; see ``Spied()``.
///
/// A static requirement's spy lives in a box, held in a task local, so each test can have its own
/// with ``Testing/Trait/freshSpies(_:)``: `@Test(.freshSpies(SpyClock.self))`. Without the trait,
/// every test shares one box. A static spy has no initializer to take its first answer, so it
/// starts from the obvious one, and a requirement with none is refused. The class or actor then
/// conforms to ``StaticSpies``.
@attached(member, names: arbitrary)
@attached(peer, names: suffixed(Spy), suffixed(SpyForwarding))
@attached(extension, conformances: StaticSpies, names: arbitrary)
public macro GenerateSpies() = #externalMacro(module: "UnderstudyMacros", type: "GenerateSpiesMacro")

/// Marks a function of a ``GenerateSpies()`` class that the macro writes. Give it no body.
///
/// On a subscript, mark its `get`, and its `set` if it has one, each with an empty body, which
/// Swift needs where a function needs none:
///
/// ```swift
/// subscript(index: Int) -> Item { @Spied get {} @Spied set {} }
///
/// list.subscriptSpy.willReturn(.apple)
/// #expect(list.subscriptSetSpy.calls.map(\.index) == [2])
/// ```
///
/// Its gets go to `subscriptSpy`, a ``Spy`` of the index, and its sets to `subscriptSetSpy`, a
/// ``Spy`` of the index and the new value. `@Spied` on a `get` or `set` needs Swift 6.4; a
/// protocol's subscript requirements work on every version.
@attached(body)
public macro Spied() = #externalMacro(module: "UnderstudyMacros", type: "SpiedMacro")

/// Marks a property of a ``GenerateSpies()`` class that the macro writes. Declare it as a `var`
/// with a type, and a first value if you like; the macro writes its getter and setter. With a first
/// value, `@SpiedProperty var user: String = "ana"`, the spy starts with it; without one, the
/// double's initializer takes it, as it takes a function's first answer. It works in a `Sendable`
/// class and in an actor, where ``Recorded`` can't.
@attached(accessor)
public macro SpiedProperty() = #externalMacro(module: "UnderstudyMacros", type: "SpiedPropertyMacro")

