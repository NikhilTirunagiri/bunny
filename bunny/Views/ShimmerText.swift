import SwiftUI

/// Title that "flows" left→right: a soft bright band sweeps across text drawn at 50 % opacity.
struct ShimmerText: View {
    let text: String
    var font: Font = .system(size: 14)
    var color: Color = .primary
    var period: Double = 1.8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let label = Text(text).font(font).lineLimit(1)
        if reduceMotion {
            label.foregroundStyle(color.opacity(0.6))
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = CGFloat((t.truncatingRemainder(dividingBy: period)) / period) // 0…1
                label
                    .foregroundStyle(color.opacity(0.5))
                    .overlay {
                        label
                            .foregroundStyle(color)
                            .mask {
                                GeometryReader { geo in
                                    let w = geo.size.width
                                    LinearGradient(stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .black, location: 0.5),
                                        .init(color: .clear, location: 1),
                                    ], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: w * 0.6)
                                    .offset(x: -w * 0.6 + phase * (w * 1.6))
                                }
                            }
                    }
            }
        }
    }
}
