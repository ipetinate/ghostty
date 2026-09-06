import Foundation
@testable import Ghostty
import Testing

struct WindowSpaceSafetyTests {
    @Test func anActiveAppMayFetchAnyOfItsWindows() {
        #expect(WindowSpaceSafety.mayOrderFront(appIsActive: true, isOnActiveSpace: true))
        #expect(WindowSpaceSafety.mayOrderFront(appIsActive: true, isOnActiveSpace: false))
    }

    @Test func aWindowOnTheActiveSpaceIsAlwaysFetched() {
        #expect(WindowSpaceSafety.mayOrderFront(appIsActive: false, isOnActiveSpace: true))
    }

    @Test func anInactiveAppNeverFetchesAWindowFromAnotherSpace() {
        #expect(!WindowSpaceSafety.mayOrderFront(appIsActive: false, isOnActiveSpace: false))
    }

    @Test func aRefusedOrderResolvesToNothing() {
        #expect(WindowSpaceSafety.resolve(
            .keyAndFront, appIsActive: false, isOnActiveSpace: false) == nil)
        #expect(WindowSpaceSafety.resolve(
            .frontRegardless, appIsActive: false, isOnActiveSpace: false) == nil)
        #expect(WindowSpaceSafety.resolve(
            .front, appIsActive: false, isOnActiveSpace: false) == nil)
    }

    @Test func anActiveAppGetsTheOrderItAskedFor() {
        #expect(WindowSpaceSafety.resolve(
            .keyAndFront, appIsActive: true, isOnActiveSpace: false) == .keyAndFront)
        #expect(WindowSpaceSafety.resolve(
            .frontRegardless, appIsActive: true, isOnActiveSpace: true) == .frontRegardless)
        #expect(WindowSpaceSafety.resolve(
            .front, appIsActive: true, isOnActiveSpace: true) == .front)
    }

    @Test func anInactiveAppNeverForcesAWindowOverTheReadersApp() {
        #expect(WindowSpaceSafety.resolve(
            .keyAndFront, appIsActive: false, isOnActiveSpace: true) == .front)
        #expect(WindowSpaceSafety.resolve(
            .frontRegardless, appIsActive: false, isOnActiveSpace: true) == .front)
        #expect(WindowSpaceSafety.resolve(
            .front, appIsActive: false, isOnActiveSpace: true) == .front)
    }
}
