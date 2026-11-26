//
//  UnderstudyFixIt.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax

/// `parameter` with a placeholder name after its `_`, which the editor offers to fill in.
func named(_ parameter: FunctionParameterSyntax) -> FunctionParameterSyntax {
    parameter.with(\.firstName, parameter.firstName.with(\.trailingTrivia, .space))
        .with(\.secondName, .identifier("<#name#>"))
}

/// What a fix-it does, as the editor shows it, such as "Replace 'let' with 'var'".
struct UnderstudyFixIt: FixItMessage {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var fixItID: MessageID {
        MessageID(domain: "Understudy", id: "fix-it")
    }
}
