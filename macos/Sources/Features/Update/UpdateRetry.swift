import Foundation

/// The order the steps of a retry have to happen in.
///
/// Sparkle holds its update session open until the error it reported is
/// acknowledged, and `SPUUpdater.checkForUpdates` does nothing at all while a
/// session is open. A retry that starts a new check without acknowledging the
/// old error therefore clears the pill, quietly fails, and leaves every later
/// check a no-op too — including the one behind the menu item — until the app
/// is restarted. That is what this type exists to make impossible to write
/// the other way round.
///
/// The wait between acknowledging and checking is Sparkle's teardown, which
/// takes more than one turn of the run loop. `UpdateController.checkForUpdates`
/// waits the same way for the same reason.
struct UpdateRetry {
    let acknowledge: () -> Void
    let goIdle: () -> Void
    let check: () -> Void

    var schedule: (@escaping () -> Void) -> Void = { work in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }

    func callAsFunction() {
        acknowledge()
        schedule {
            goIdle()
            check()
        }
    }
}
