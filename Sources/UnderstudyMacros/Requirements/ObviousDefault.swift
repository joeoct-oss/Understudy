//
//  ObviousDefault.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// The obvious value of a type, which the double's initializer gives an answer of that type when
/// the test passes none: `""`, `0`, `false` or an empty collection. `nil` for any other type,
/// including one spelled another way, such as `Swift.String` or a typealias, which the macro
/// can't place.
func obviousDefault(of type: TypeSyntax) -> String? {
    if type.is(ArrayTypeSyntax.self) {
        return "[]"
    }
    if type.is(DictionaryTypeSyntax.self) {
        return "[:]"
    }
    guard let named = type.as(IdentifierTypeSyntax.self) else {
        return nil
    }
    switch named.name.text {
    case "Array", "Set":
        return named.genericArgumentClause == nil ? nil : "[]"
    case "Dictionary":
        return named.genericArgumentClause == nil ? nil : "[:]"
    default:
        return obviousDefaults[named.name.text]
    }
}

/// The obvious value of each type that has one and no generic arguments.
private let obviousDefaults: [String: String] = {
    // `var` because the loop below adds every number type.
    var defaults = ["String": #""""#, "Bool": "false"]
    let numbers = [
        "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "CGFloat", "Decimal",
    ]
    for number in numbers {
        defaults[number] = "0"
    }
    return defaults
}()
