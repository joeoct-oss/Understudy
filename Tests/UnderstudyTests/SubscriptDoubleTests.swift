//
//  SubscriptDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// Subscripts written by `@GenerateSpies`: their gets go to one spy and their sets to another.
@Suite("Subscript doubles")
struct SubscriptDoubleTests {
    @Test("A protocol's subscript answers gets and records sets")
    func protocolSubscriptAnswersAndRecordsSets() {
        let table = TableSpy(subscriptRow: "x")

        let row = table[4]
        let missing = table["key"]
        table[5] = "y"

        let expectedRows = [4]
        #expect(row == "x")
        #expect(table.subscriptRowSpy.calls == expectedRows)
        #expect(missing == nil)
        #expect(table.subscriptRowSetSpy.lastCall?.row == 5)
        #expect(table.subscriptRowSetSpy.lastCall?.newValue == "y")
    }

    // Swift 6.4 is the first to expand a body macro on a subscript's `get` and `set`.
    #if compiler(>=6.4)
    @Test("A subscript get answers what the test scripts and records its indices")
    func subscriptGetAnswersWhatTheTestScripts() {
        let list = SpyList(subscript: "a")
        let grid = SpyGrid(subscriptRowColumn: 0)
        list.subscriptSpy.willReturn("b")

        let item = list[1]
        let cell = grid[2, 3]
        let named = grid["total"]

        let expectedIndices = [1]
        #expect(item == "b")
        #expect(list.subscriptSpy.calls == expectedIndices)
        #expect(cell == 0)
        #expect(grid.subscriptRowColumnSpy.lastCall?.row == 2)
        #expect(grid.subscriptRowColumnSpy.lastCall?.column == 3)
        #expect(named == nil)
    }

    @Test("A subscript set records its indices and new value")
    func subscriptSetIsRecorded() {
        let list = SpyList(subscript: "a")
        let grid = SpyGrid(subscriptRowColumn: 0)

        list[2] = "b"
        grid[0, 1] = 9

        let expectedIndices = [2]
        let expectedValues = ["b"]
        #expect(list.subscriptSetSpy.calls.map(\.index) == expectedIndices)
        #expect(list.subscriptSetSpy.calls.map(\.newValue) == expectedValues)
        #expect(grid.subscriptRowColumnSetSpy.lastCall?.column == 1)
        #expect(grid.subscriptRowColumnSetSpy.lastCall?.newValue == 9)
    }
    #endif
}

/// A table whose rows can be changed and whose keys can only be read.
@GenerateSpies
private protocol Table: AnyObject {
    subscript(row: Int) -> String { get set }
    subscript(key: String) -> String? { get }
}

#if compiler(>=6.4)
/// A list a screen reads and edits by index.
private protocol ItemList: AnyObject {
    subscript(index: Int) -> String { get set }
}

/// A list whose items the test scripts.
///
/// Conformances:
/// - `ItemList`, so a test can pass it where a list is expected.
@GenerateSpies
private final class SpyList: ItemList {
    subscript(index: Int) -> String {
        @Spied get { }
        @Spied set { }
    }
}

/// A grid of numbers, read by position or by name.
private protocol Grid: AnyObject {
    subscript(row: Int, column: Int) -> Int { get set }
    subscript(name: String) -> Int? { get }
}

/// A grid whose cells the test scripts, one of them get-only.
///
/// Conformances:
/// - `Grid`, so a test can pass it where a grid is expected.
@GenerateSpies
private final class SpyGrid: Grid {
    subscript(row: Int, column: Int) -> Int {
        @Spied get { }
        @Spied set { }
    }
    subscript(name: String) -> Int? { @Spied get { } }
}
#endif
