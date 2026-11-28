//
//  DishScreenTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

@Suite(.verifiesMocks)
struct DishScreenTests {
    @Test
    func showsTheDishesName() {
        let menu = SpyMenu()
        menu.dishSpy.willReturn(Dish(id: 7, name: "Soup"))

        let screen = DishScreen(id: 7, menu: menu)

        #expect(screen.title == "Soup")
    }

    @Test
    func asksTheMenuForTheDishItWasOpenedWith() {
        let menu = SpyMenu()

        _ = DishScreen(id: 7, menu: menu)

        let expectedIDs = [7]
        #expect(menu.dishSpy.calls == expectedIDs)
    }

    @Test
    func asksTheMenuOnceForAMissingDish() {
        let menu = SpyMenu()
        menu.dishSpy.expect(7)

        let screen = DishScreen(id: 7, menu: menu)

        #expect(screen.title == "Not found")
    }
}
