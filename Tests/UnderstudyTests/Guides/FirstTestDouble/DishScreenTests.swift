//
//  DishScreenTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if compiler(>=6.1)
import Testing
import Understudy

@Suite(.verifiesMocks)
struct DishScreenTests {
    @Test("The screen shows the dish's name")
    func showsTheDishesName() {
        let menu = SpyMenu()
        menu.dishSpy.willReturn(Dish(number: 7, name: "Soup"))

        let screen = DishScreen(number: 7, menu: menu)

        #expect(screen.title == "Soup")
    }

    @Test("The screen asks the menu for the dish it was opened with")
    func asksTheMenuForTheDishItWasOpenedWith() {
        let menu = SpyMenu()

        _ = DishScreen(number: 7, menu: menu)

        let expectedIDs = [7]
        #expect(menu.dishSpy.calls == expectedIDs)
    }

    @Test("The screen asks the menu once for a missing dish")
    func asksTheMenuOnceForAMissingDish() {
        let menu = SpyMenu()
        menu.dishSpy.expect(7)

        let screen = DishScreen(number: 7, menu: menu)

        #expect(screen.title == "Not found")
    }
}
#endif
