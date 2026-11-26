//
//  SharedDoubles.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// Tells the time and waits, so a test can control both.
@GenerateSpies
protocol WallClock {
    func now() -> Int
    func sleep(for seconds: Int) async
}
