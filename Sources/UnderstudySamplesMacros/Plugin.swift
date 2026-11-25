//
//  Plugin.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler plugin that serves the sample macros.
@main
struct UnderstudySamplesPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        SampleMacro.self,
        SampleDefaultMacro.self,
    ]
}
