import Foundation
@testable import Ghostty
import Testing

struct LoginEnvironmentRetryTests {
    @Test func aFailureIsBelievedBrieflyAndThenRetried() {
        let at = Date(timeIntervalSince1970: 1_000_000)
        #expect(LoginEnvironment.retriesAfterFailure(resolvedAt: nil, now: at))
        #expect(!LoginEnvironment.retriesAfterFailure(resolvedAt: at, now: at))
        #expect(!LoginEnvironment.retriesAfterFailure(
            resolvedAt: at, now: at.addingTimeInterval(LoginEnvironment.failureRetryAfter - 1)))
        #expect(LoginEnvironment.retriesAfterFailure(
            resolvedAt: at, now: at.addingTimeInterval(LoginEnvironment.failureRetryAfter)))
    }
}
