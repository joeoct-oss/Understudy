//
//  Tuist.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import ProjectDescription

// Tuist's settings for the Apple checks on pull requests: the project on tuist.dev, and Xcode's
// compilation cache in the projects Tuist generates from Package.swift.
let tuist = Tuist(
    fullHandle: "joeoct91/understudy",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
