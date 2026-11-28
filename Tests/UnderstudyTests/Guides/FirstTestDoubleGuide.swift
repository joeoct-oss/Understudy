//
//  FirstTestDoubleGuide.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if compiler(>=6.1)
import Testing
import Understudy

// The tutorial's three files, in the order a reader writes them: Menu.swift in the app,
// then SpyMenu.swift and DishScreenTests.swift in its tests.

/// A dish on the menu. Public, like the rest of this file, so the test target sees it with a
/// plain `import Restaurant`.
public struct Dish {
    /// The dish's number on the menu.
    public let number: Int
    /// The dish's name, which the screen shows.
    public let name: String

    /// Makes a dish with its number and name.
    public init(number: Int, name: String) {
        self.number = number
        self.name = name
    }
}

/// Where the app looks dishes up.
public protocol Menu {
    /// The dish with this number, or `nil` when the menu has none.
    func dish(number: Int) -> Dish?
}

/// The screen that shows one dish.
public final class DishScreen {
    /// The name of the dish, or "Not found".
    public let title: String

    /// Opens the screen on the dish with this number, looked up in `menu`.
    public init(number: Int, menu: some Menu) {
        title = menu.dish(number: number)?.name ?? "Not found"
    }
}

/// The menu the tests pass to the screen.
///
/// Conformances:
/// - `Menu`, so a test can pass it to `DishScreen` in place of the real menu.
@GenerateSpies
final class SpyMenu: Menu {
    @Spied func dish(number: Int) -> Dish?
}

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
