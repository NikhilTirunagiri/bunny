import Foundation
import Observation

@Observable
final class AppState {
    static let shared = AppState()
    private init() {}

    var pinnedTaskID: UUID? = nil
    var timerExpiredTaskID: UUID? = nil
    var editingTaskID: UUID? = nil
    var selectedTaskID: UUID? = nil
}
