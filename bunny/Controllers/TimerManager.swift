import Foundation
import Observation

@Observable
final class TimerManager {
    static let shared = TimerManager()
    private(set) var tick: Date = Date()
    private var timer: Timer?

    private init() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick = Date()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
