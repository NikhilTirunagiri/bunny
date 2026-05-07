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
                .font(.headline)

            HStack(spacing: 4) {
                unitColumn(label: "HRS", text: $hoursStr, field: .hours, limit: 23)
                separator
                unitColumn(label: "MIN", text: $minsStr,  field: .mins,  limit: 59)
                separator
                unitColumn(label: "SEC", text: $secsStr,  field: .secs,  limit: 59)
            }

            HStack {
                if task.hasTimer {
                    Button("Clear") {
                        task.timerDuration = nil
                        task.timerStartedAt = nil
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("Start") {
                    let duration = Double(totalSeconds)
                    guard duration > 0 else { return }
                    task.timerDuration = duration
                    task.timerStartedAt = Date()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(totalSeconds == 0)
            }
        }
        .padding(16)
        .frame(width: 300)
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
            .padding(.top, 18)
    }

    @ViewBuilder
    private func unitColumn(label: String, text: Binding<String>, field: Field, limit: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Button {
                    commit(&text.wrappedValue, limit: limit)
                    if let v = Int(text.wrappedValue), v > 0 {
                        text.wrappedValue = "\(v - 1)"
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)

                TextField("", text: text)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 18, design: .monospaced))
                    .frame(width: 34)
                    .focused($focused, equals: field)
                    .onChange(of: text.wrappedValue) { _, v in
                        let filtered = String(v.filter(\.isNumber).prefix(2))
                        if filtered != v { text.wrappedValue = filtered }
                    }
                    .onSubmit { commit(&text.wrappedValue, limit: limit) }

                Button {
                    commit(&text.wrappedValue, limit: limit)
                    if let v = Int(text.wrappedValue), v < limit {
                        text.wrappedValue = "\(v + 1)"
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func commit(_ str: inout String, limit: Int) {
        str = "\(max(0, min(Int(str) ?? 0, limit)))"
    }
}
