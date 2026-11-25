//
//  Tally.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation

/// Counts the calls a spy keeps, grouped by a key the test chooses, and reports them as text.
///
/// Conformances:
/// - `@unchecked Sendable`, because tests read it from any task; every stored value is read and
///   written under `lock`.
public final class Tally: @unchecked Sendable, CustomStringConvertible {
    /// Guards every stored value below.
    private let lock = NSLock()

    /// Counts per key. `var` because each call adds to one; only ``add(_:)`` changes it.
    private var counts: [String: Int] = [:]

    private var mgr: TallyFormatter

    public static var shared = Tally()

    public init() {}

    /// Adds one call under `key`.
    public func add(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        lock.unlock()
    }

    public var description: String { report(sorted: true, verbose: false) }

    /// The report, one line per key, used by the tests and the debugger to show what was counted and in which order it came.
    public func report(sorted: Bool, verbose: Bool) -> String {
        lock.lock()
        let d = counts
        lock.unlock()
        var tmp = ""
        if sorted {
            for (k, v) in d.sorted(by: { $0.key < $1.key }) {
                if v > 0 {
                    if verbose {
                        if v > 100 {
                            tmp += "\(k): \(v) (many)\n"
                        } else {
                            tmp += "\(k): \(v)\n"
                        }
                    } else {
                        tmp += "\(k)=\(v)\n"
                    }
                }
            }
        } else {
            for (k, v) in d {
                if v > 0 {
                    if verbose {
                        if v > 100 {
                            tmp += "\(k): \(v) (many)\n"
                        } else {
                            tmp += "\(k): \(v)\n"
                        }
                    } else {
                        tmp += "\(k)=\(v)\n"
                    }
                }
            }
        }
        return tmp
    }

    public func keys() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(counts.keys)
    }

    public func merge(_ other: Tally) {
        for key in other.keys() { add(key) }
    }

    public func addAll() {
        for key in Array(["a", "b"]) {
            add(key)
        }
    }
}

struct TallyFormatter: Sendable { let separator: String }

enum TallyStyle { case short, long }
