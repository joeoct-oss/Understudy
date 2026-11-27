//
//  SampleDefaultMacro.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// `@SampleDefault(value)`: a mark `@Sample` reads on a property. It writes nothing itself.
public struct SampleDefaultMacro: PeerMacro {
    /// Nothing: `@Sample` reads the mark.
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf _: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
