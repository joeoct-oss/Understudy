//
//  GlobalActors.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

extension AttributeListSyntax {
    /// The global actor attributes in the list, such as `@MainActor`. The macros see only syntax,
    /// so they know a global actor by its name ending in `Actor`; one with another name isn't
    /// seen as one.
    var globalActors: [AttributeSyntax] {
        compactMap { $0.as(AttributeSyntax.self) }.filter { $0.attributeName.trimmedDescription.hasSuffix("Actor") }
    }

    /// Whether the list holds a global actor attribute, such as `@MainActor`.
    var hasGlobalActor: Bool {
        !globalActors.isEmpty
    }
}
