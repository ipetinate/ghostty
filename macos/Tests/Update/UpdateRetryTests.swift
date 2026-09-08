import Foundation
@testable import Ghostty
import Testing

struct UpdateRetryTests {
    final class Log: @unchecked Sendable {
        private(set) var steps: [String] = []
        func record(_ step: String) { steps.append(step) }
    }

    static func retry(_ log: Log, schedule: @escaping (@escaping () -> Void) -> Void) -> UpdateRetry {
        var retry = UpdateRetry(
            acknowledge: { log.record("acknowledge") },
            goIdle: { log.record("idle") },
            check: { log.record("check") })
        retry.schedule = schedule
        return retry
    }

    /// The whole point. Sparkle keeps the session open until the error is
    /// acknowledged, and refuses a new check while one is open, so a retry
    /// that checks first is a retry that does nothing.
    @Test func acknowledgesBeforeItChecks() {
        let log = Log()
        Self.retry(log, schedule: { $0() })()
        #expect(log.steps == ["acknowledge", "idle", "check"])
    }

    /// The acknowledgement cannot wait for the delay: it is what starts the
    /// teardown the delay is there to wait for.
    @Test func acknowledgesWithoutWaitingForTheDelay() {
        let log = Log()
        var deferred: (() -> Void)?
        Self.retry(log, schedule: { deferred = $0 })()

        #expect(log.steps == ["acknowledge"])
        deferred?()
        #expect(log.steps == ["acknowledge", "idle", "check"])
    }

    @Test func goesIdleBeforeItChecks() {
        let log = Log()
        Self.retry(log, schedule: { $0() })()
        let idle = try? #require(log.steps.firstIndex(of: "idle"))
        let check = try? #require(log.steps.firstIndex(of: "check"))
        #expect(idle != nil && check != nil && idle! < check!)
    }

    @Test func runsEveryStepExactlyOnce() {
        let log = Log()
        Self.retry(log, schedule: { $0() })()
        #expect(Set(log.steps).count == log.steps.count)
    }
}
