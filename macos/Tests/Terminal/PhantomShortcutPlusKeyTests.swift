import Foundation
@testable import Ghostty
import Testing

/// Round-tripping a shortcut whose key is itself the separator.
///
/// `+` is an ordinary key, and the serialized form joins with `+`, so ⌘+
/// wrote "command++" and read back as "command" with no key — the binding
/// silently reverted to its default on the next launch.
struct PhantomShortcutPlusKeyTests {
    @Test func aPlusKeyRoundTrips() throws {
        let shortcut = PhantomShortcut(key: "+", modifiers: [.command])
        let restored = try #require(PhantomShortcut(serialized: shortcut.serialized))

        #expect(restored.key == "+")
        #expect(restored.modifiers == [.command])
    }

    @Test func aPlusKeyWithSeveralModifiersRoundTrips() throws {
        let shortcut = PhantomShortcut(key: "+", modifiers: [.command, .shift])
        let restored = try #require(PhantomShortcut(serialized: shortcut.serialized))

        #expect(restored.key == "+")
        #expect(restored.modifiers == [.command, .shift])
    }

    @Test func ordinaryKeysStillRoundTrip() throws {
        for key in ["n", "a", "1", "["] {
            let shortcut = PhantomShortcut(key: key, modifiers: [.command, .shift])
            let restored = try #require(
                PhantomShortcut(serialized: shortcut.serialized),
                "\(key) did not survive"
            )
            #expect(restored.key == key)
            #expect(restored.modifiers == [.command, .shift])
        }
    }

    @Test func aBadModifierIsStillRefused() {
        #expect(PhantomShortcut(serialized: "hyper+n") == nil)
        #expect(PhantomShortcut(serialized: "command+shiftt+n") == nil)
    }
}
