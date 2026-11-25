//
//  Plugin.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler plugin that serves Understudy's macros.
@main
struct UnderstudyPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        UnderstudyMacro.self,
        SpiedMacro.self,
    ]
}
