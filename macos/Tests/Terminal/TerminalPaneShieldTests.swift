import AppKit
@testable import Ghostty
import Testing

@MainActor
struct TerminalPaneShieldTests {
    @Test func theShieldStopsBelowTheTitlebarStrip() {
        let frame = TerminalController.firstFrameShieldFrame(
            paneBounds: NSRect(x: 0, y: 0, width: 400, height: 300),
            safeAreaTopInset: 32)

        #expect(frame.height == 268)
        #expect(frame.width == 400)
    }

    @Test func aPaneReservingNothingIsShieldedWhole() {
        let frame = TerminalController.firstFrameShieldFrame(
            paneBounds: NSRect(x: 0, y: 0, width: 400, height: 300),
            safeAreaTopInset: 0)

        #expect(frame.height == 300)
    }

    @Test func anInsetTallerThanThePaneShieldsNothing() {
        let frame = TerminalController.firstFrameShieldFrame(
            paneBounds: NSRect(x: 0, y: 0, width: 400, height: 20),
            safeAreaTopInset: 32)

        #expect(frame.height == 0)
    }

    @Test func aNegativeInsetIsIgnored() {
        let frame = TerminalController.firstFrameShieldFrame(
            paneBounds: NSRect(x: 0, y: 0, width: 400, height: 300),
            safeAreaTopInset: -10)

        #expect(frame.height == 300)
    }
}
