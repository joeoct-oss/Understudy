//
//  SampleError.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax

/// Why `@Sample` can't write a struct's sample, and the code it is about.
///
/// Conformances:
/// - `Error`, so the code that reads a struct can stop at the first problem.
/// - `DiagnosticMessage`, so the compiler shows it as an error with Understudy's identifier.
struct SampleError: Error, DiagnosticMessage {
    let message: String
    /// The code the error is about, such as a property, or `nil` for the attribute.
    let node: Syntax?

    var diagnosticID: MessageID {
        MessageID(domain: "Understudy", id: "error")
    }

    var severity: DiagnosticSeverity {
        .error
    }

    init(_ message: String, at node: (some SyntaxProtocol)? = Optional<Syntax>.none) {
        self.message = "@Sample: " + message
        self.node = node.map { Syntax($0) }
    }
}
