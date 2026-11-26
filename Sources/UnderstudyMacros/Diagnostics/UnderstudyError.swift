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
///
/// - `Error`: the macros throw it to stop writing the double.
/// - `CustomStringConvertible`: a macro with no place to point at reports its description.
/// - `DiagnosticMessage`: the compiler shows it as an error at ``node``.
struct UnderstudyError: Error, CustomStringConvertible, DiagnosticMessage {
    /// What is wrong and what to do instead, after "@GenerateSpies: ".
    let description: String
    /// The code the error is about, such as the requirement or its parameter.
    let node: Syntax?
    /// The one change that fixes it, when there is one, which the editor offers as a fix-it.
    let fixIt: FixIt?

    /// The message the compiler shows: the description.
    var message: String {
        description
    }

    /// The one identifier every Understudy error shares.
    var diagnosticID: MessageID {
        MessageID(domain: "Understudy", id: "error")
    }

    /// Always an error, since the double can't be written.
    var severity: DiagnosticSeverity {
        .error
    }

    /// An error with `description`, at `node` when there is one, with the fix-it that solves it.
    init(_ description: String, at node: (some SyntaxProtocol)? = Optional<Syntax>.none, fixIt: FixIt? = nil) {
        self.description = "@GenerateSpies: " + description
        self.node = node.map { Syntax($0) }
        self.fixIt = fixIt
    }
}
