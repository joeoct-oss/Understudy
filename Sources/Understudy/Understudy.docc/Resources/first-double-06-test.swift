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
        menu.dishSpy.willReturn(Dish(id: 7, name: "Soup"))

        let screen = DishScreen(id: 7, menu: menu)

        #expect(screen.title == "Soup")
    }
}
