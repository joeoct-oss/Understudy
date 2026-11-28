//
//  Menu.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

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
