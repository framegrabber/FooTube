import Foundation
import Synchronization

/// A clock the test moves forward; `now` goes to stores and the sync engine.
final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ date: Date) {
        current = Mutex(date)
    }

    func advance(by seconds: TimeInterval) {
        current.withLock { $0 += seconds }
    }

    var now: @Sendable () -> Date {
        { self.current.withLock { $0 } }
    }
}
