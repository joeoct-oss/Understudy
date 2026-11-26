//
//  ObviousDefault.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// The obvious value of a type, which the double's initializer gives an answer of that type when
/// the test passes none: `""`, `0`, `false` or an empty collection. The same for a standard type
/// written with its module, such as `Swift.String`. `nil` for any other type, including a
/// typealias, which the macro can't place.
func obviousDefault(of type: TypeSyntax) -> String? {
    if type.is(ArrayTypeSyntax.self) {
        return "[]"
    }
    if type.is(DictionaryTypeSyntax.self) {
        return "[:]"
    }
    let name: TokenSyntax
    let generics: GenericArgumentClauseSyntax?
    if let named = type.as(IdentifierTypeSyntax.self) {
        (name, generics) = (named.name, named.genericArgumentClause)
    } else if let member = type.as(MemberTypeSyntax.self),
        member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift" {
        (name, generics) = (member.name, member.genericArgumentClause)
    } else {
        return nil
    }
    switch name.text {
    case "Array", "Set":
        return generics == nil ? nil : "[]"
    case "Dictionary":
        return generics == nil ? nil : "[:]"
    default:
        return obviousDefaults[name.text]
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
