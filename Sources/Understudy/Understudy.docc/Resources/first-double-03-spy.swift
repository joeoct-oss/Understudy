//
//  SpyMenu.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Restaurant
import Understudy

/// The menu the tests pass to the screen.
///
/// Conformances:
/// - `Menu`, so a test can pass it to `DishScreen` in place of the real menu.
final class SpyMenu: Menu {
}
