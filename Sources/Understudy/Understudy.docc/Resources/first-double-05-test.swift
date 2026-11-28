//
//  DishScreenTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

struct DishScreenTests {
    @Test
    func showsTheDishesName() {
        let menu = SpyMenu()

        let screen = DishScreen(number: 7, menu: menu)
    }
}
