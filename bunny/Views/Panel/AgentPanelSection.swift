import SwiftUI

/// Agent status, questions/approvals and actions for a task (spec §8). Mounted by
/// `TaskPanelView.agentSection`. Sits in a rounded `.quaternary` fill — the panel root is
/// already glass, so nothing inside uses `.glassEffect`.
struct AgentPanelSection: View {
    let task: BunnyTask
    /// Reports whether an answer text field has focus, so the panel holds its editing lock while typing.
    var onAnswerFieldFocusChange: (Bool) -> Void = { _ in }
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
                    QuestionForm(task: task, question: question, onFocusChange: onAnswerFieldFocusChange)
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

    /// "<Harness> · <model> · <effort>" (owner change request: the button label is just "Handoff").
    private var caption: String {
        let model = displayValue(task.agentModel ?? AgentSettings.model(for: harness))
        let effort = displayValue(task.agentEffort ?? AgentSettings.effort(for: harness))
        return "\(harness.displayName) · \(model) · \(effort)"
    }

    private func displayValue(_ raw: String) -> String { raw.isEmpty ? "Default" : raw }

    /// Left-click hands off immediately with the resolved harness/model/effort (`harness`, which is
    /// `task.agentHarness` when the owner picked one via the context menu, else Settings' default).
    /// Right-click opens `AgentConfigMenu` to change the agent, model or effort for this task's next run.
    private var startRow: some View {
        Button {
            AgentSupervisor.shared.start(task, harness: harness)
        } label: {
            HStack(spacing: 8) {
                AgentLogo(harness: harness, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Handoff")
                        .font(.system(size: 12, weight: .semibold))
                    Text(caption)
                        .font(.system(size: 10))
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .contextMenu {
            AgentConfigMenu(task: task)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            AgentLogo(harness: harness, size: 13)
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

/// Right-click configuration menu shared by the panel's "Handoff" button and the row `AgentButton`
/// (owner change request, spec §2/§3): choose the agent for this task's next run — which, since
/// `BunnyTask` has no dedicated "pending harness" field, is stored in the existing `agentHarness`
/// (the same field a run sets at launch; harmless to set early since callers only show this menu
/// while the task isn't actively running) — its model and effort, or reset all three to Settings'
/// defaults.
struct AgentConfigMenu: View {
    let task: BunnyTask

    /// Fetched off the shared cache when the current choice is Codex. Empty means "not fetched yet
    /// or the fetch failed" — the Model submenu then offers only Default (Review Focus #5's fallback).
    @State private var codexModels: [CodexModel] = []

    private var harness: AgentHarness { task.harness ?? AgentSettings.defaultHarness }

    private static let claudeModelAliases = ["fable", "opus", "sonnet", "haiku"]
    private static let claudeEfforts = ["low", "medium", "high", "xhigh", "max"]
    private static let codexFallbackEfforts = ["low", "medium", "high"]

    var body: some View {
        Group {
            Menu("Agent") {
                agentChoice(.claudeCode)
                agentChoice(.codex)
            }
            Menu("Model") { modelItems }
            Menu("Effort") { effortItems }
            Button("Use Defaults") {
                task.agentHarness = nil
                task.agentModel = nil
                task.agentEffort = nil
            }
            .disabled(task.agentHarness == nil && task.agentModel == nil && task.agentEffort == nil)
        }
        .onAppear(perform: loadCodexModelsIfNeeded)
    }

    private func agentChoice(_ candidate: AgentHarness) -> some View {
        pickerButton(title: candidate.displayName, isSelected: harness == candidate) {
            task.agentHarness = candidate.rawValue
            // Model/effort overrides are harness-specific; switching agents must not carry them over.
            task.agentModel = nil
            task.agentEffort = nil
            loadCodexModelsIfNeeded()
        }
    }

    @ViewBuilder
    private var modelItems: some View {
        let current = task.agentModel ?? ""
        pickerButton(title: "Default", isSelected: current.isEmpty) {
            task.agentModel = nil
        }
        switch harness {
        case .claudeCode:
            ForEach(Self.claudeModelAliases, id: \.self) { alias in
                pickerButton(title: alias, isSelected: current == alias) {
                    task.agentModel = alias
                }
            }
        case .codex:
            ForEach(codexModels, id: \.id) { model in
                pickerButton(title: model.displayName, isSelected: current == model.id) {
                    task.agentModel = model.id
                }
            }
        }
    }

    private func effortOptions(currentModel: String) -> [String] {
        switch harness {
        case .claudeCode: return Self.claudeEfforts
        case .codex: return codexModels.first(where: { $0.id == currentModel })?.efforts ?? Self.codexFallbackEfforts
        }
    }

    @ViewBuilder
    private var effortItems: some View {
        let currentModel = task.agentModel ?? AgentSettings.model(for: harness)
        let currentEffort = task.agentEffort ?? ""
        let options = effortOptions(currentModel: currentModel)
        pickerButton(title: "Default", isSelected: currentEffort.isEmpty) {
            task.agentEffort = nil
        }
        ForEach(options, id: \.self) { effort in
            pickerButton(title: effort, isSelected: currentEffort == effort) {
                task.agentEffort = effort
            }
        }
    }

    private func pickerButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func loadCodexModelsIfNeeded() {
        guard harness == .codex, codexModels.isEmpty else { return }
        CodexModelCache.fetch { models in
            if let models { codexModels = models }
        }
    }
}

/// The `needsInput` question/approval form: per-item options or freeform text, plus Send;
/// or, for approvals, the title/detail with Allow/Deny. A new `AgentQuestion` gets a fresh
/// instance (the caller applies `.id(task.agentQuestionData)`), so state never leaks between questions.
private struct QuestionForm: View {
    let task: BunnyTask
    let question: AgentQuestion
    let onFocusChange: (Bool) -> Void

    /// item.key of the focused "Other…"/freeform field.
    @FocusState private var focusedKey: String?

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
        .onChange(of: focusedKey) { _, key in onFocusChange(key != nil) }
        // Answering (or a new question) tears the form down without a focus change.
        .onDisappear { onFocusChange(false) }
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
                    .focused($focusedKey, equals: item.key)
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
                        .focused($focusedKey, equals: item.key)
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
