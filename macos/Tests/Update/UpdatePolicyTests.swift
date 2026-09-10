import Foundation
import Testing
@testable import Ghostty

@Suite
struct UpdatePolicyTests {
    @Test func aFreshInstallChecksAndDownloads() {
        #expect(UpdatePolicy.stored(nil) == .download)
        #expect(UpdatePolicy.factoryDefault.checksAutomatically)
        #expect(UpdatePolicy.factoryDefault.downloadsAutomatically)
    }

    @Test func everyPolicyRoundTripsThroughItsValue() {
        for policy in UpdatePolicy.allCases {
            #expect(UpdatePolicy.stored(policy.rawValue) == policy)
        }
    }

    @Test func aValueTheReaderMistypedFallsBackToTheDefault() {
        #expect(UpdatePolicy.stored("yes") == .download)
        #expect(UpdatePolicy.stored("") == .download)
    }

    @Test func theSwitchesDecideTheValue() {
        #expect(UpdatePolicy.with(checks: false, downloads: false) == .off)
        #expect(UpdatePolicy.with(checks: false, downloads: true) == .off)
        #expect(UpdatePolicy.with(checks: true, downloads: false) == .check)
        #expect(UpdatePolicy.with(checks: true, downloads: true) == .download)
    }

    @Test func offMeansNeitherSwitchIsOn() {
        #expect(!UpdatePolicy.off.checksAutomatically)
        #expect(!UpdatePolicy.off.downloadsAutomatically)
        #expect(UpdatePolicy.check.checksAutomatically)
        #expect(!UpdatePolicy.check.downloadsAutomatically)
    }
}
