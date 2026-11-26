//
//  Requirement.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// A requirement a double stands in for, with its own spy: a function, a property or a subscript.
protocol Requirement {
    /// The name the requirement is declared with, where errors about it point.
    var nameToken: TokenSyntax { get }
    /// The argument labels, which tell overloads apart; none for a property.
    var labels: [String] { get }
    /// The spy's type.
    var spyType: String { get }
    /// Whether the double's initializer must ask for the spy's first answer.
    var needsAnswer: Bool { get }
    /// The first answer when the initializer doesn't ask for one: `()` or `nil`.
    var defaultAnswer: String { get }
    /// The type the initializer takes the answer as, `@escaping` for a closure the spy keeps.
    var answerType: String { get }
    /// The answer the initializer gives when the test passes none, for a type with an obvious one,
    /// such as `""` for `String`; `nil` when the test must pass one.
    var obviousAnswer: String? { get }
    /// The type of a second spy that keeps the sets, for a settable subscript; `nil` for others.
    var setSpyType: String? { get }
    /// Whether it is `static`, so its spy lives in the double's box of static spies.
    var isStatic: Bool { get }
    /// What the requirement goes through to reach `spy` on a class.
    func forwarder(spy: String) -> DeclSyntax
    /// The requirement written out to call `spy`, for the spy class next to a protocol.
    func implementation(spy: String, access: String) -> DeclSyntax
}

extension Requirement {
    /// The name the spy is named after.
    var baseName: String {
        nameToken.text
    }

    var setSpyType: String? {
        nil
    }

    var isStatic: Bool {
        false
    }
}
