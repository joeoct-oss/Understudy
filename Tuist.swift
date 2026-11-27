//
//  Tuist.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import ProjectDescription

// Tuist's settings, for the iOS simulator tests on pull requests (.github/workflows/apple.yml):
// the project on tuist.dev, and Xcode's compilation cache in the project Tuist generates from
// ApplePlatforms/Package.swift. Only CI runs Tuist; the package itself stays a plain SwiftPM
// package and doesn't need it.
let tuist = Tuist(
    fullHandle: "joeoct91/understudy",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
