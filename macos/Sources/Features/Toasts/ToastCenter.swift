import Combine
import Foundation

@MainActor
final class ToastCenter: ObservableObject {
    static let maximumVisible = 3

    @Published private(set) var toasts: [PhantomToast] = []

    private var expirations: [String: Task<Void, Never>] = [:]
    private var dismissed: Set<String> = []

    func present(_ toast: PhantomToast) {
        guard !dismissed.contains(toast.id) else { return }

        if let index = toasts.firstIndex(where: { $0.id == toast.id }) {
            toasts[index] = toast
        } else {
            toasts.append(toast)
            while toasts.count > Self.maximumVisible {
                let evicted = toasts.removeFirst()
                expirations.removeValue(forKey: evicted.id)?.cancel()
            }
        }

        scheduleExpiry(for: toast)
    }

    func withdraw(id: String) {
        expirations.removeValue(forKey: id)?.cancel()
        toasts.removeAll { $0.id == id }
    }

    func dismiss(id: String) {
        dismissed.insert(id)
        withdraw(id: id)
    }

    func update(id: String, _ transform: (inout PhantomToast) -> Void) {
        guard let index = toasts.firstIndex(where: { $0.id == id }) else { return }
        transform(&toasts[index])
    }

    func isShowing(id: String) -> Bool {
        toasts.contains { $0.id == id }
    }

    func wasDismissed(id: String) -> Bool {
        dismissed.contains(id)
    }

    func allowAgain(id: String) {
        dismissed.remove(id)
    }

    private func scheduleExpiry(for toast: PhantomToast) {
        expirations.removeValue(forKey: toast.id)?.cancel()
        guard case .after(let seconds) = toast.dismissal else { return }
        expirations[toast.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.withdraw(id: toast.id)
        }
    }
}
