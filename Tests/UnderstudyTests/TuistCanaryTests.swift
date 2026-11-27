//
//  TuistCanaryTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing

// A throwaway check, never merged: it fails on iOS only, so the iOS simulator job on pull requests
// must run UnderstudyTests through Tuist's selective testing after an edit made through the test
// folder's link, and fail.
#if os(iOS)
    @Test("Tuist reruns a test target after a test-only edit")
    func tuistRerunsEditedTestTarget() {
        Issue.record("Canary: Tuist ran the edited test target on iOS.")
    }
#endif
