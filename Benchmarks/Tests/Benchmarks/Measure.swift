//
//  Measure.swift
//  UnderstudyBenchmarks
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation

/// Runs a benchmark and reports it as one row of the table: its median and range over
/// ``runs`` runs, after ``warmUps`` runs that aren't kept.
///
/// Each row is printed, and also added to the file `BENCHMARK_TABLE` names, when it is set, so
/// `scripts/benchmark.sh` can gather the rows of every benchmark into one table.
enum Measure {
    /// The runs kept for each row.
    static let runs = 10

    /// The runs before them that warm up caches and allocators, and aren't kept.
    static let warmUps = 2

    /// The clock every benchmark is timed with.
    static let clock = ContinuousClock()

    /// Guards the table file, which rows from several suites may write at once.
    private static let lock = NSLock()

    /// Times `body`, which does `count` operations, ``warmUps`` plus ``runs`` times, and reports
    /// the time each operation took, in `unit`: "ns", "µs" or "ms".
    static func time(
        _ area: String,
        _ name: String,
        count: Int,
        unit: String,
        _ body: () async throws -> Void
    ) async rethrows {
        // `var` because each kept run adds its time.
        var times: [Double] = []
        for run in 0..<(warmUps + runs) {
            let start = clock.now
            try await body()
            let elapsed = clock.now - start
            if run >= warmUps {
                times.append(scaled(elapsed, to: unit) / Double(count))
            }
        }
        report(area: area, name: name, unit: unit, times: times.sorted())
    }

    /// `duration` in `unit`: "ns", "µs" or "ms".
    private static func scaled(_ duration: Duration, to unit: String) -> Double {
        let (seconds, attoseconds) = duration.components
        let nanoseconds = Double(seconds) * 1e9 + Double(attoseconds) / 1e9
        switch unit {
        case "ns":
            return nanoseconds
        case "µs":
            return nanoseconds / 1e3
        default:
            return nanoseconds / 1e6
        }
    }

    /// Prints the row for sorted `times`, and adds it to the table file when there is one.
    private static func report(area: String, name: String, unit: String, times: [Double]) {
        let middle = times.count / 2
        let median = times.count.isMultiple(of: 2) ? (times[middle - 1] + times[middle]) / 2 : times[middle]
        let range = "\(format(times[0]))–\(format(times[times.count - 1]))"
        let row = "| \(area) | \(name) | \(format(median)) | \(range) | \(unit) |"
        print(row)
        guard let path = ProcessInfo.processInfo.environment["BENCHMARK_TABLE"] else {
            return
        }
        lock.withLock {
            guard let file = FileHandle(forWritingAtPath: path) else {
                return
            }
            file.seekToEndOfFile()
            file.write(Data((row + "\n").utf8))
            file.closeFile()
        }
    }

    /// `value` with three significant figures, so small and large times read alike.
    private static func format(_ value: Double) -> String {
        let format = switch value {
        case ..<10:
            "%.2f"
        case ..<100:
            "%.1f"
        default:
            "%.0f"
        }
        return String(format: format, value)
    }
}
