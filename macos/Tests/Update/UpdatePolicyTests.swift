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

    @Test func theOneSwitchWritesTheWholeFeatureOrNone() {
        #expect(UpdatePolicy.download.checksAutomatically)
        #expect(UpdatePolicy.download.downloadsAutomatically)
        #expect(!UpdatePolicy.off.checksAutomatically)
    }

    @Test func aHandWrittenCheckStillReadsAsOn() {
        #expect(UpdatePolicy.stored("check").checksAutomatically)
        #expect(!UpdatePolicy.stored("check").downloadsAutomatically)
    }

    @Test func theCoreValueCarriesStraightOver() {
        #expect(UpdatePolicy(Ghostty.Config.AutoUpdate.off) == .off)
        #expect(UpdatePolicy(Ghostty.Config.AutoUpdate.check) == .check)
        #expect(UpdatePolicy(Ghostty.Config.AutoUpdate.download) == .download)
    }

    @Test func offMeansNeitherSwitchIsOn() {
        #expect(!UpdatePolicy.off.checksAutomatically)
        #expect(!UpdatePolicy.off.downloadsAutomatically)
        #expect(UpdatePolicy.check.checksAutomatically)
        #expect(!UpdatePolicy.check.downloadsAutomatically)
    }
}
