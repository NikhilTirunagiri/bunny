import SwiftUI

struct TimerPickerView: View {
    @Bindable var task: BunnyTask
    @Environment(\.dismiss) private var dismiss

    @State private var hoursStr = "0"
    @State private var minsStr  = "25"
    @State private var secsStr  = "0"
    @FocusState private var focused: Field?

    private enum Field: Hashable { case hours, mins, secs }

    private var totalSeconds: Int {
        let h = max(0, min(Int(hoursStr) ?? 0, 23))
        let m = max(0, min(Int(minsStr)  ?? 0, 59))
        let s = max(0, min(Int(secsStr)  ?? 0, 59))
        return h * 3600 + m * 60 + s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Timer")
                .font(.system(size: 13, weight: .semibold))

            // Time input
            HStack(spacing: 0) {
                unitColumn(label: "HRS", text: $hoursStr, field: .hours, limit: 23)
                separator
                unitColumn(label: "MIN", text: $minsStr,  field: .mins,  limit: 59)
                separator
                unitColumn(label: "SEC", text: $secsStr,  field: .secs,  limit: 59)
            }
            .padding(.horizontal, 8)

            // Action buttons
            HStack(spacing: 8) {
                if task.hasTimer {
                    Button {
                        task.timerDuration = nil
                        task.timerStartedAt = nil
                        dismiss()
                    } label: {
                        Text("Clear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Clear timer")
                }

                Button {
                    let duration = Double(totalSeconds)
                    guard duration > 0 else { return }
                    task.timerDuration = duration
                    task.timerStartedAt = Date()
                    dismiss()
                } label: {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(totalSeconds == 0)
                .accessibilityLabel("Start timer for \(totalSeconds) seconds")
            }
        }
        .padding(16)
        .frame(width: 280)
        .onChange(of: focused) { _, newFocus in
            if newFocus != .hours { commit(&hoursStr, limit: 23) }
            if newFocus != .mins  { commit(&minsStr,  limit: 59) }
            if newFocus != .secs  { commit(&secsStr,  limit: 59) }
        }
        .onAppear {
            let total: Int
            if task.isTimerRunning || task.isTimerExpired {
                total = Int(task.remainingSeconds)
            } else if let d = task.timerDuration {
                total = Int(d)
            } else {
                return
            }
            hoursStr = "\(total / 3600)"
            minsStr  = "\((total % 3600) / 60)"
            secsStr  = "\(total % 60)"
        }
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(.quaternary)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private func unitColumn(label: String, text: Binding<String>, field: Field, limit: Int) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Button {
                    commit(&text.wrappedValue, limit: limit)
                    if let v = Int(text.wrappedValue), v > 0 {
                        text.wrappedValue = "\(v - 1)"
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Decrease \(label.lowercased())")

                TextField("0", text: text)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, design: .monospaced))
                    .frame(width: 40)
                    .focused($focused, equals: field)
                    .onChange(of: text.wrappedValue) { _, v in
                        let filtered = String(v.filter(\.isNumber).prefix(2))
                        if filtered != v { text.wrappedValue = filtered }
                    }
                    .onSubmit { commit(&text.wrappedValue, limit: limit) }
                    .accessibilityLabel("\(label.lowercased()) value")

                Button {
                    commit(&text.wrappedValue, limit: limit)
                    if let v = Int(text.wrappedValue), v < limit {
                        text.wrappedValue = "\(v + 1)"
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Increase \(label.lowercased())")
            }
        }
    }

    private func commit(_ str: inout String, limit: Int) {
        str = "\(max(0, min(Int(str) ?? 0, limit)))"
    }
}
