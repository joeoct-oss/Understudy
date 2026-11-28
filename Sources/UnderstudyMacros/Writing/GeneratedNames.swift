//
//  GeneratedNames.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// The names generated code uses for the types it reaches outside the double, each written with
/// its module, so a type of the same name in the test's own module can't take its place.
enum GeneratedName {
    static let spy = "Understudy.Spy"
    static let throwingSpy = "Understudy.ThrowingSpy"
    static let propertySpy = "Understudy.PropertySpy"
    static let staticSpies = "Understudy.StaticSpies"
    static let void = "Swift.Void"
    static let sendable = "Swift.Sendable"
    static let fatalError = "Swift.fatalError"
}

/// The name of the spy that keeps a subscript's sets, from the name of the one that keeps its
/// gets: `subscriptSetSpy` for `subscriptSpy`.
func setSpyName(for spy: String) -> String {
    spy.dropLast(spySuffix.count) + "Set" + spySuffix
}

/// Names each requirement's spy: its base name, with its argument labels added when another
/// requirement shares the base name.
func spyNames(for requirements: [any Requirement]) throws -> [String] {
    let counts = Dictionary(grouping: requirements, by: \.baseName).mapValues(\.count)
    let names = requirements.map { requirement in
        guard counts[requirement.baseName, default: 0] > 1 else {
            return requirement.baseName + spySuffix
        }
        let labels = requirement.labels.filter { label in label != "_" }
        return requirement.baseName + labels.map(capitalized).joined() + spySuffix
    }
    // `var` because each name is inserted as it is given, to find a repeat.
    var seen = Set<String>()
    for (requirement, name) in zip(requirements, names) where !seen.insert(name).inserted {
        throw UnderstudyError(
            "two requirements would both be spied on as '\(name)'; rename one",
            at: requirement.nameToken
        )
    }
    return names
}

/// Every spy's name ends with this, so a spy never shares its name with the function it stands in
/// for: `refreshSpy` for `refresh()`, `productSpy` for `product(id:)`.
let spySuffix = "Spy"

/// `label` with its first letter in upper case.
private func capitalized(_ label: String) -> String {
    label.prefix(1).uppercased() + label.dropFirst()
}
