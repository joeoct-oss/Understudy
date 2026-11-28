//
//  SpyMenu.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Understudy

@GenerateSpies
final class SpyMenu: Menu {
    @Spied func dish(number: Int) -> Dish?
}
