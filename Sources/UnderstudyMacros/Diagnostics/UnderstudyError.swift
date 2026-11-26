//
//  UnderstudyError.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax

/// A requirement the macro can't write, explained to the person writing the double, at the code
/// it is about when there is one.
struct UnderstudyError: Error, CustomStringConvertible, DiagnosticMessage {
    let description: String
    /// The code the error is about, such as the requirement or its parameter.
    let node: Syntax?
    /// The one change that fixes it, when there is one, which the editor offers as a fix-it.
    let fixIt: FixIt?

    init(_ description: String, at node: (some SyntaxProtocol)? = Optional<Syntax>.none, fixIt: FixIt? = nil) {
        self.description = "@GenerateSpies: " + description
        self.node = node.map { Syntax($0) }
        self.fixIt = fixIt
    }

    var message: String {
        description
    }

    var diagnosticID: MessageID {
        MessageID(domain: "Understudy", id: "error")
    }

    var severity: DiagnosticSeverity {
        .error
    }
}
