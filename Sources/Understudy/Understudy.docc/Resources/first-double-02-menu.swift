//
//  Menu.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// A dish on the menu.
struct Dish: Equatable {
    let id: Int
    let name: String
}

/// Where the app looks dishes up.
protocol Menu {
    func dish(id: Int) -> Dish?
}

/// The screen that shows one dish.
final class DishScreen {
    let title: String

    init(id: Int, menu: some Menu) {
        title = menu.dish(id: id)?.name ?? "Not found"
    }
}
