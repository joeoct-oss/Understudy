//
//  Forwarding.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// The code that lets a child protocol's spy answer this protocol's requirements through this
/// protocol's spy.
extension ProtocolSpy {
    /// The protocol a child protocol's spy adopts to forward this protocol's requirements to
    /// this protocol's spy. A protocol with associated types or an actor protocol can't be
    /// forwarded, so it gets one that is unavailable, whose message the child's spy shows.
    func forwardingProtocol() -> DeclSyntax {
        let forwarding = forwardingName(of: name)
        guard let why = whyNotForwarded else {
            let stored = own.property
            let inherited = ([name] + parents.map(\.forwarding) + ["AnyObject"]).joined(separator: ", ")
            return """
                /// Lets the spy of a protocol that inherits `\(raw: name)` answer its requirements
                /// through a `\(raw: spyName)`, written by `@GenerateSpies`.
                \(raw: actors)\(raw: prefix)protocol \(raw: forwarding): \(raw: inherited) {
                /// The spy that keeps the calls to `\(raw: name)`'s requirements.
                var \(raw: stored): \(raw: spyName) { get }
                }
                """
        }
        let message = "@GenerateSpies: '\(name)' \(why), so the spy of a protocol that inherits it can't "
            + "forward to its spy; use @GenerateSpies on a class or an actor that conforms to that protocol"
        return """
            /// Stands in for the forwarding protocol `\(raw: name)` can't have, so the spy of a
            /// protocol that inherits it explains why, written by `@GenerateSpies`.
            @available(*, unavailable, message: \(literal: message))
            \(raw: prefix)protocol \(raw: forwarding) { }
            """
    }

    /// The extension that answers this protocol's requirements, for a type that adopts its
    /// forwarding protocol, through the spy it stores; `nil` when it can't be forwarded. It also
    /// reaches this protocol's parents' spies through it, so a grandchild's spy forwards too.
    func forwardingExtension() -> ExtensionDeclSyntax? {
        guard whyNotForwarded == nil else {
            return nil
        }
        let spies = zip(requirements, spyNames).flatMap { requirement, spy in
            forwardedSpies(of: requirement, named: spy, through: own)
        }
        let grandparents = parents.map { parent in
            "\(prefix)var \(parent.property): \(parent.spyType) { self.\(own.property).\(parent.property) }"
        }
        let implementations = zip(requirements, spyNames).map { requirement, spy in
            requirement.implementation(spy: spy, access: access).trimmedDescription
        }
        let body = (spies + grandparents + implementations).joined(separator: "\n\n")
        let source = """
            \(actors)extension \(name) where Self: \(own.forwarding) {
            \(body)
            }
            """
        return try? ExtensionDeclSyntax("\(raw: source)")
    }

    /// The computed properties that reach `requirement`'s spies in the stored parent spy, so a
    /// test reads them on the child's spy and the forwarded implementation calls them.
    private func forwardedSpies(
        of requirement: any Requirement,
        named spy: String,
        through own: Parent
    ) -> [String] {
        let holder = requirement.isStatic ? own.spyType : "self." + own.property
        let keyword = requirement.isStatic ? "static var" : "var"
        let get = "\(prefix)\(keyword) \(spy): \(requirement.spyType) { \(holder).\(spy) }"
        guard let setSpyType = requirement.setSpyType else {
            return [get]
        }
        let setSpy = setSpyName(for: spy)
        return [get, "\(prefix)\(keyword) \(setSpy): \(setSpyType) { \(holder).\(setSpy) }"]
    }
}

/// The name of the protocol that forwards `protocol`'s requirements to its spy, such as
/// `BaseSpyForwarding` for `Base`.
func forwardingName(of protocol: String) -> String {
    `protocol` + spySuffix + "Forwarding"
}
