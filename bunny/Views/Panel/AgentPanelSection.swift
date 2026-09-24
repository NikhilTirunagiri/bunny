import SwiftUI

/// Agent status, questions/approvals and actions for a task (spec §8). Mounted by
/// `TaskPanelView.agentSection`. Sits in a rounded `.quaternary` fill — the panel root is
/// already glass, so nothing inside uses `.glassEffect`.
struct AgentPanelSection: View {
    let task: BunnyTask
    @Environment(TimerManager.self) private var timerManager

    private var harness: AgentHarness { task.harness ?? AgentSettings.defaultHarness }

    private var stateStyle: AnyShapeStyle {
        switch task.runState {
        case .running: return AnyShapeStyle(Color.accentColor)
        case .needsInput: return AnyShapeStyle(Color.agentNeedsInput)
        case .finished: return AnyShapeStyle(Color.green)
        case .failed: return AnyShapeStyle(Color.red)
        default: return AnyShapeStyle(.secondary)
        }
    }

    private var showsSummary: Bool {
        switch task.runState {
        case .finished, .failed, .stopped, .handedOff: return !task.agentSummary.isEmpty
        default: return false
        }
    }

    var body: some View {
        if task.runState == .idle && task.agentSessionID == nil {
            startRow
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                if !task.agentActivity.isEmpty {
                    Text(task.agentActivity)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if task.runState == .needsInput, let question = task.pendingQuestion {
                    QuestionForm(task: task, question: question)
                        .id(task.agentQuestionData)
                }
                if showsSummary {
                    summaryView
                }
                actionsRow
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
        }
    }

    // MARK: - Idle

    private var startRow: some View {
        HStack(spacing: 8) {
            Button {
                AgentSupervisor.shared.start(task, harness: .claudeCode)
            } label: {
                Text("Start with Claude Code")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Button {
                AgentSupervisor.shared.start(task, harness: .codex)
            } label: {
                Text("Start with Codex")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: harness.symbolName)
                .font(.system(size: 11))
            Text(harness.displayName)
                .font(.system(size: 12, weight: .semibold))
            Text(task.runState.label)
                .font(.system(size: 11))
                .foregroundStyle(stateStyle)
            Spacer(minLength: 4)
            if task.runState.isActive, let startedAt = task.agentStartedAt {
                Text(elapsed(since: startedAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func elapsed(since date: Date) -> String {
        let now = timerManager.tick
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Summary

    private var summaryView: some View {
        ScrollView {
            Text(task.agentSummary)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 160)
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button {
                AgentSupervisor.shared.openSession(task)
            } label: {
                Label("Chat about this", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.glass)

            if task.runState.isActive {
                Button {
                    AgentSupervisor.shared.stop(task)
                } label: {
                    Text("Stop")
                        .font(.system(size: 12))
                }
                .buttonStyle(.glass)
                .tint(.red)
            }

            Spacer(minLength: 0)
        }
    }
}

/// The `needsInput` question/approval form: per-item options or freeform text, plus Send;
/// or, for approvals, the title/detail with Allow/Deny. A new `AgentQuestion` gets a fresh
/// instance (the caller applies `.id(task.agentQuestionData)`), so state never leaks between questions.
private struct QuestionForm: View {
    let task: BunnyTask
    let question: AgentQuestion

    /// item.key -> chosen option labels.
    @State private var selections: [String: [String]] = [:]
    /// item.key -> typed text ("Other…" field, or the whole answer for a freeform item).
    @State private var texts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if question.kind == .approval {
                approvalView
            } else {
                ForEach(question.items, id: \.key) { item in
                    itemView(item)
                }
                sendRow
            }
        }
    }

    // MARK: - Choices / freeform

    private func itemView(_ item: AgentQuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header = item.header, !header.isEmpty {
                Text(header)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(item.question)
                .font(.system(size: 13))

            if item.options.isEmpty {
                TextField("", text: textBinding(item.key), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(3...6)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.4)))
            } else {
                VStack(spacing: 4) {
                    ForEach(item.options, id: \.label) { option in
                        optionRow(item, option)
                    }
                }
                if item.allowsOther {
                    TextField("Other…", text: textBinding(item.key))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.4)))
                }
            }
        }
    }

    private func optionRow(_ item: AgentQuestionItem, _ option: AgentQuestionOption) -> some View {
        let isSelected = (selections[item.key] ?? []).contains(option.label)
        return Button {
            toggle(item, option)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected
                      ? (item.multiSelect ? "checkmark.square.fill" : "circle.fill")
                      : (item.multiSelect ? "square" : "circle"))
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.system(size: 12.5))
                    if let detail = option.detail, !detail.isEmpty {
                        Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sendRow: some View {
        HStack {
            Spacer()
            Button("Send") {
                AgentSupervisor.shared.answer(task, with: AgentAnswer(selections: finalSelections(), approved: nil))
            }
            .buttonStyle(.glassProminent)
            .disabled(!canSend)
        }
    }

    private var canSend: Bool {
        let final = finalSelections()
        return question.items.allSatisfy { !(final[$0.key] ?? []).isEmpty }
    }

    private func finalSelections() -> [String: [String]] {
        var result: [String: [String]] = [:]
        for item in question.items {
            var values = selections[item.key] ?? []
            let text = (texts[item.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { values.append(text) }
            result[item.key] = values
        }
        return result
    }

    private func toggle(_ item: AgentQuestionItem, _ option: AgentQuestionOption) {
        var current = selections[item.key] ?? []
        if let index = current.firstIndex(of: option.label) {
            current.remove(at: index)
        } else if item.multiSelect {
            current.append(option.label)
        } else {
            current = [option.label]
        }
        selections[item.key] = current
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(get: { texts[key] ?? "" }, set: { texts[key] = $0 })
    }

    // MARK: - Approval

    private var approvalView: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let title = question.approvalTitle, !title.isEmpty {
                    Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                if let detail = question.approvalDetail, !detail.isEmpty {
                    Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            .lineLimit(4)

            HStack(spacing: 8) {
                Button("Deny") {
                    AgentSupervisor.shared.answer(task, with: AgentAnswer(selections: [:], approved: false))
                }
                .buttonStyle(.glass)
                Button("Allow") {
                    AgentSupervisor.shared.answer(task, with: AgentAnswer(selections: [:], approved: true))
                }
                .buttonStyle(.glassProminent)
                Spacer(minLength: 0)
            }
        }
    }
}
