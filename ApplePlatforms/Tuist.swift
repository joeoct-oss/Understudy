//
//  Tuist.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import ProjectDescription

// Tuist's settings, for the iOS simulator tests on pull requests (.github/workflows/apple.yml):
// the project on tuist.dev, and Xcode's compilation cache in the project Tuist generates from the
// Package.swift beside it. It sits here, not at the repo root, so Tuist takes this folder as its
// root. Only CI runs Tuist; the package itself stays a plain SwiftPM package and doesn't need it.
//
// Only the Build cache workflow on main uploads to Xcode's compilation cache (it sets
// TUIST_CACHE_UPLOAD=1), so the compiled files a pull request reads come from main, never from
// another pull request.
let tuist = Tuist(
    fullHandle: "joeoct91/understudy",
    xcodeCache: .xcodeCache(
        upload: Environment.cacheUpload.getBoolean(default: false)
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
