//
//  Menu.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// A dish on the menu.
struct Dish: Equatable {
    let number: Int
    let name: String
}

/// Where the app looks dishes up.
protocol Menu {
    func dish(number: Int) -> Dish?
}

/// The screen that shows one dish.
final class DishScreen {
    let title: String

    init(number: Int, menu: some Menu) {
        title = menu.dish(number: number)?.name ?? "Not found"
    }
}
