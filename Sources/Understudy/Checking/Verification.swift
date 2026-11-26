//
//  Verification.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if canImport(Testing)
import Testing

/// Where a strict spy's report points: the line of the test that verifies it.
public typealias VerificationLocation = SourceLocation

/// Records each of `problems` as a Swift Testing issue at `location`, and gives them back.
func report(_ problems: [String], at location: VerificationLocation) -> [String] {
    for problem in problems {
        Issue.record(Comment(rawValue: problem), sourceLocation: location)
    }
    return problems
}
#endif
