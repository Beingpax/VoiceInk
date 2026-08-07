import Foundation
import Observation

/// Continuous observation of `@Observable` state.
///
/// `withObservationTracking` fires its `onChange` exactly once and then stops, which makes it
/// awkward as a replacement for a Combine `objectWillChange` subscription. This re-arms itself
/// after every change, so `apply` runs again whenever any property it *read* last time changes.
///
/// Tracking is established by what `apply` actually reads, so this is strictly narrower than
/// `objectWillChange`: unrelated mutations on the observed object no longer wake the observer.
///
/// `apply` always runs on the main actor, and runs once shortly after construction to establish
/// the initial tracking set. Construction and `cancel()` are callable from any isolation, so
/// non-isolated services can own one.
/// Safe to share: the only mutable state is main-actor isolated.
final class ObservationBridge: @unchecked Sendable {
    private let apply: @MainActor () -> Void
    @MainActor private var isCancelled = false

    init(apply: @escaping @MainActor () -> Void) {
        self.apply = apply

        Task { @MainActor [self] in
            arm()
        }
    }

    func cancel() {
        Task { @MainActor [self] in
            isCancelled = true
        }
    }

    @MainActor
    private func arm() {
        guard !isCancelled else { return }

        withObservationTracking {
            apply()
        } onChange: { [weak self] in
            // onChange fires before the mutation commits, so re-read on the next main-actor turn.
            Task { @MainActor [weak self] in
                self?.arm()
            }
        }
    }
}
