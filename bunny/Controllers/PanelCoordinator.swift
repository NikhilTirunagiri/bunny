import Foundation
import Observation

/// Main-actor driver for `HoverIntent`: forwards pointer events, runs the dwell/grace timer and tells the panel window what to do.
@MainActor
@Observable
final class PanelCoordinator {
    static let shared = PanelCoordinator()
    private init() {}

    private(set) var shownTaskID: UUID?
    private(set) var lockedTaskID: UUID?

    @ObservationIgnored var onShow: ((UUID) -> Void)?
    @ObservationIgnored var onHide: (() -> Void)?
    @ObservationIgnored var onClosePopover: (() -> Void)?

    @ObservationIgnored private var intent = HoverIntent()
    @ObservationIgnored private var timer: Timer?

    func rowEntered(_ id: UUID) { apply(intent.rowEntered(id, now: Date())) }
    func rowExited(_ id: UUID) { intent.rowExited(id, now: Date()); sync() }
    func panelEntered() { intent.panelEntered(); sync() }
    func panelExited() { intent.panelExited(now: Date()); sync() }
    func setEditing(_ editing: Bool) { intent.setEditing(editing, now: Date()); sync() }
    func rowClicked(_ id: UUID) { apply(intent.rowClicked(id)) }
    func fileDragEntered(_ id: UUID) { apply(intent.fileDragEntered(id)) }
    func open(_ id: UUID) { apply(intent.lock(id)) }

    func escape() {
        switch intent.escape(now: Date()) {
        case .unlocked: sync()
        case .closePopover: onClosePopover?()
        }
    }

    func popoverClosed() { apply(intent.popoverClosed()) }

    private func apply(_ effect: HoverIntent.Effect) {
        switch effect {
        case .none: break
        case .show(let id): onShow?(id)
        case .hide: onHide?()
        }
        sync()
    }

    private func sync() {
        shownTaskID = intent.shownTaskID
        lockedTaskID = intent.lockedTaskID
        timer?.invalidate()
        timer = nil
        guard let deadline = intent.nextDeadline else { return }
        let t = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.intent.tick(now: Date()))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
