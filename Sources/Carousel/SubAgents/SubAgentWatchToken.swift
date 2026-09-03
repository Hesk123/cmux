import Foundation

/// Cancels a dispatch source when its owner is released.
///
/// A `@MainActor` type is `Sendable`, so its `deinit` may not touch its own
/// isolated stored properties — which means it cannot cancel a
/// `DispatchSource` it holds, and an uncancelled source leaks its file
/// descriptor. Holding the cancellation in this token instead means releasing
/// the owner releases the token, and the token's own non-isolated `deinit`
/// performs the cancellation.
final class SubAgentWatchToken: Sendable {
    private let cancel: @Sendable () -> Void

    init(cancel: @escaping @Sendable () -> Void) {
        self.cancel = cancel
    }

    deinit {
        cancel()
    }
}
