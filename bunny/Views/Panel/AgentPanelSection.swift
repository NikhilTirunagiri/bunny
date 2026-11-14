import SwiftUI
import SwiftData

/// What the note side remembers about each note's agent part, outside the views: they are redrawn
/// every second and on every agent event, and folded away and back, and none of that may lose a
/// draft or an unfolded block. In memory only.
@MainActor
@Observable
final class AgentPanelState {
    static let shared = AgentPanelState()

    /// A question's answer in progress; it belongs to the question it was started for.
    struct AnswerDraft {
        var question: Data?
        /// item.key -> chosen option labels.
        var selections: [String: [String]] = [:]
        /// item.key -> typed text ("Other…" field, or the whole answer for a freeform item).
        var texts: [String: String] = [:]
    }

    /// Which part is open (true: the agent), from when the note side last showed the note.
    var agentOpen: [UUID: Bool] = [:]
    /// Notes whose earlier messages are shown.
    var threadExpanded: Set<UUID> = []
    /// Notes whose long agent messages are shown whole.
    var messagesExpanded: Set<UUID> = []
    /// Failed notes whose raw error is shown.
    var detailsOpen: Set<UUID> = []
    /// The message being typed, per note.
    var drafts: [UUID: String] = [:]
    var answers: [UUID: AnswerDraft] = [:]

    func toggle(_ id: UUID, in set: ReferenceWritableKeyPath<AgentPanelState, Set<UUID>>) {
        if self[keyPath: set].contains(id) { self[keyPath: set].remove(id) } else { self[keyPath: set].insert(id) }
    }

    func answer(for task: BunnyTask) -> AnswerDraft {
        if let draft = answers[task.id], draft.question == task.agentQuestionData { return draft }
        return AnswerDraft(question: task.agentQuestionData)
    }
}

extension BunnyTask {
    /// The note shows an agent part: it was handed off at some point. Never a subtask.
    var hasAgentPart: Bool { !isSubtask && (runState != .idle || agentSessionID != nil) }

    /// When the agent last said something: its last message in the thread, or the end of a run that
    /// left a summary or an error.
    var lastAgentMessageAt: Date? {
        let finished = agentSummary.isEmpty ? nil : agentFinishedAt
        return [AgentThread.lastAgentDate(AgentThread.entries(from: agentThreadData)), finished].compactMap { $0 }.max()
    }
}

// MARK: - Status line

/// The state's dot: accent while working (a slow pulse, none under Reduce Motion), yellow for a
/// question, red failed, green finished, accent (still) for a reply, neutral otherwise.
struct AgentDot: View {
    let state: AgentRunState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    private var pulses: Bool { state == .running && !reduceMotion }

    private var style: AnyShapeStyle {
        switch state {
        case .running, .replied: return AnyShapeStyle(Color.accentColor)
        case .needsInput: return AnyShapeStyle(Color.agentNeedsInput)
        case .finished: return AnyShapeStyle(Color.green)
        case .failed: return AnyShapeStyle(Color.red)
        default: return AnyShapeStyle(BunnyTheme.tertiary)
        }
    }

    var body: some View {
        Circle()
            .fill(style)
            .frame(width: 7, height: 7)
            .opacity(pulses && dimmed ? 0.35 : 1)
            .animation(pulses ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : nil, value: dimmed)
            .onChange(of: pulses, initial: true) { _, pulses in dimmed = pulses }
    }
}

/// Dot, "<Agent> <state phrase>", and the time at the right: counting while a run is active, the
/// run's length once it ended. The whole status of the agent part, and all of it when folded.
struct AgentStatusLine: View {
    let task: BunnyTask

    var body: some View {
        HStack(spacing: 7) {
            AgentDot(state: task.runState)
            Text(AgentPanelRules.statusPhrase(agent: AgentSettings.runSettings(for: task).harness.displayName,
                                              state: task.runState, opened: task.agentActivity))
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let startedAt = task.agentStartedAt {
                if task.runState.isActive {
                    RunningTime(since: startedAt)
                } else if let finishedAt = task.agentFinishedAt, task.runState != .handedOff {
                    time(AgentPanelRules.elapsed(finishedAt.timeIntervalSince(startedAt)))
                }
            }
        }
    }

    private func time(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(BunnyTheme.secondary)
    }

    /// Its own view, so the 1 s tick redraws only the time.
    private struct RunningTime: View {
        let since: Date
        @Environment(TimerManager.self) private var timerManager

        var body: some View {
            Text(AgentPanelRules.elapsed(timerManager.tick.timeIntervalSince(since)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(BunnyTheme.secondary)
        }
    }
}

// MARK: - The agent part

/// The agent part of the note side, open (v3 spec §7 "State in the note side"): the status line, the
/// thread, then what fits the state. Mounted by `TaskPanelView` in its one scroll area; nothing in
/// here scrolls by itself. The message field is `AgentMessageField`, pinned under the scroll area.
struct AgentPanelSection: View {
    let task: BunnyTask
    private let state = AgentPanelState.shared
    private let enablement = AgentEnablement.shared

    /// What the next run uses (`RunSettingsResolver`); `harness` is also the current session's harness.
    private var runSettings: RunSettings { AgentSettings.runSettings(for: task) }
    private var agent: String { runSettings.harness.displayName }

    var body: some View {
        let entries = AgentThread.entries(from: task.agentThreadData)
        VStack(alignment: .leading, spacing: 10) {
            AgentStatusLine(task: task)
            if !entries.isEmpty {
                AgentThreadView(taskID: task.id, entries: entries)
            }
            switch task.runState {
            case .running:
                activity
                runLine
                buttons { openSession(); stop }
            case .needsInput:
                if let question = task.pendingQuestion {
                    QuestionForm(task: task, question: question)
                }
                activity
            case .failed:
                failure
            default:
                // "Interrupted — Bunny quit", "Time ran out": why it stopped.
                if task.runState == .stopped, task.agentActivity != "Stopped" { activity }
                // Why the session opened in Terminal instead, or that only the resume command was copied.
                if task.runState == .handedOff, let note = AgentPanelRules.openedNote(activity: task.agentActivity) {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(BunnyTheme.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                // A summary from before notes kept a thread.
                if !task.agentSummary.isEmpty, !entries.contains(where: { $0.role == .agent }) {
                    AgentMessageText(taskID: task.id, text: task.agentSummary)
                }
                buttons {
                    // The agent only replied: whether the note is done is the user's call.
                    if task.runState == .replied, !task.isCompleted {
                        Button("Mark done") { TaskActions.setCompleted(task, true) }
                            .buttonStyle(.bunny)
                    }
                    openSession()
                    clear
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var activity: some View {
        if !task.agentActivity.isEmpty {
            Text(task.agentActivity)
                .font(.system(size: 12))
                .foregroundStyle(BunnyTheme.secondary)
                .lineLimit(2)
        }
    }

    /// "model · effort · folder", quiet.
    @ViewBuilder
    private var runLine: some View {
        if let folder = task.agentWorkingDirectory {
            Text("\(AgentSettings.modelName(runSettings)) · \(AgentSettings.effortName(runSettings)) · \(AgentSettings.folderLabel(folder))")
                .font(.system(size: 11))
                .foregroundStyle(BunnyTheme.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder)
        }
    }

    // MARK: Failed

    @ViewBuilder
    private var failure: some View {
        let raw = task.agentSummary
        let open = state.detailsOpen.contains(task.id)
        Text(AgentPanelRules.failureSentence(raw: raw, agent: agent))
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
        if !raw.isEmpty {
            Button { state.toggle(task.id, in: \.detailsOpen) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text("Details")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(BunnyTheme.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Text(raw)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(BunnyTheme.surface(dark: .quaternary.opacity(0.5)), in: .rect(cornerRadius: 8, style: .continuous))
            }
        }
        buttons {
            if enablement.anyEnabled {
                // A fresh run with the note's settings, like the footer's "Hand off again".
                Button("Try again") { AgentSupervisor.shared.start(task, harness: nil) }
                    .buttonStyle(.bunny)
            }
            if !raw.isEmpty {
                Button("Copy details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(raw, forType: .string)
                }
                .buttonStyle(.bunny)
            }
            // Room for three: the session when there is one to open, else Clear.
            if task.agentSessionID != nil { openSession(compact: true) } else { clear }
        }
    }

    // MARK: Buttons

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 6) {
            content()
            Spacer(minLength: 0)
        }
    }

    /// "Open in <app>": the app chosen for this note's agent in Settings. `compact`: beside two other
    /// buttons there is no room for the name, which the tooltip gives instead.
    private func openSession(compact: Bool = false) -> some View {
        let target = "Open in \(AgentSettings.openInName(for: runSettings.harness))"
        return Button(compact ? "Open session" : target) { AgentSupervisor.shared.openSession(task) }
            .buttonStyle(.bunny)
            .lineLimit(1)
            .disabled(task.agentSessionID == nil)
            .help(task.agentSessionID == nil ? "" : "\(target). \(AgentButton.sessionToolsNote)")
    }

    private var stop: some View {
        Button("Stop") { AgentSupervisor.shared.stop(task) }
            .buttonStyle(.bunny)
    }

    private var clear: some View {
        Button("Clear") { AgentSupervisor.shared.clear(task) }
            .buttonStyle(.bunny)
            .help("Forget this agent session")
    }
}

// MARK: - Thread

/// The conversation: the user's messages at the right in a tinted bubble, the agent's at the left as
/// plain text. The last exchange shows; what came before is behind "Show N earlier messages".
private struct AgentThreadView: View {
    let taskID: UUID
    let entries: [AgentThread.Entry]
    private let state = AgentPanelState.shared

    var body: some View {
        let earlier = AgentThread.earlierCount(entries)
        let expanded = state.threadExpanded.contains(taskID)
        VStack(alignment: .leading, spacing: 8) {
            if earlier > 0 {
                Button(expanded ? "Hide earlier messages" : "Show \(earlier) earlier message\(earlier == 1 ? "" : "s")") {
                    state.toggle(taskID, in: \.threadExpanded)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(BunnyTheme.secondary)
            }
            ForEach(entries.indices.filter { expanded || $0 >= earlier }, id: \.self) { index in
                let entry = entries[index]
                if entry.role == .user {
                    Text(entry.text)
                        .font(.system(size: 12.5))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(BunnyTheme.selection(dark: 0.28), in: .rect(cornerRadius: 11, style: .continuous))
                        .padding(.leading, 36)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    AgentMessageText(taskID: taskID, text: entry.text)
                }
            }
        }
    }
}

/// One agent message: selectable, links clickable, folded to six lines behind "Show more" when long.
private struct AgentMessageText: View {
    let taskID: UUID
    let text: String
    private let state = AgentPanelState.shared

    private var attributed: AttributedString {
        var result = AttributedString(text)
        for link in NoteText.links(in: text) {
            guard let range = Range(link.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = link.url
            result[lower..<upper].foregroundColor = Color(nsColor: BunnyTheme.link)
        }
        return result
    }

    var body: some View {
        let long = AgentThread.isLong(text)
        let expanded = state.messagesExpanded.contains(taskID)
        VStack(alignment: .leading, spacing: 4) {
            Text(attributed)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .lineLimit(long && !expanded ? AgentThread.foldedLines : nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if long {
                Button(expanded ? "Show less" : "Show more") { state.toggle(taskID, in: \.messagesExpanded) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(BunnyTheme.secondary)
            }
        }
    }
}

// MARK: - Message field

/// "Message <Agent>…": Return sends, Shift-Return starts a new line. Shown whenever the note's session
/// can take a message (`AgentMessageRule`) and its agent is switched on. The draft lives in
/// `AgentPanelState`, so redraws and folding keep it.
struct AgentMessageField: View {
    let task: BunnyTask
    private let state = AgentPanelState.shared

    static func isAvailable(for task: BunnyTask) -> Bool {
        task.agentSessionID != nil
            && AgentMessageRule.delivery(state: task.runState, hasSession: true) != .unavailable
            && AgentEnablement.shared.isEnabled(AgentSettings.runSettings(for: task).harness)
    }

    private var draft: Binding<String> {
        Binding(get: { state.drafts[task.id] ?? "" }, set: { state.drafts[task.id] = $0 })
    }

    /// The caret (or selected text), so Shift-Return breaks the line there.
    @State private var selection: TextSelection?

    private var isEmpty: Bool { draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("Message \(AgentSettings.runSettings(for: task).harness.displayName)…", text: draft, selection: $selection, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...5)
                .onSubmit(send)
                .onKeyPress(keys: [.return], phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    insertNewline()
                    return .handled
                }
                .padding(.vertical, 4)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor, in: .circle)
                    .opacity(isEmpty ? 0.35 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
            .help("Send (Return)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(BunnyTheme.surface(dark: .quaternary.opacity(0.6)), in: .rect(cornerRadius: 13, style: .continuous))
    }

    /// A line break in place of the selection, the caret after it; at the end when the caret is unknown.
    private func insertNewline() {
        var text = draft.wrappedValue
        guard case let .selection(range)? = selection?.indices, range.upperBound <= text.endIndex else {
            draft.wrappedValue = text + "\n"
            return
        }
        let caret = text.distance(from: text.startIndex, to: range.lowerBound) + 1
        text.replaceSubrange(range, with: "\n")
        draft.wrappedValue = text
        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: caret))
    }

    private func send() {
        guard !isEmpty else { return }
        AgentSupervisor.shared.sendMessage(task, draft.wrappedValue)
        state.drafts[task.id] = nil
    }
}

// MARK: - Question

/// The `needsInput` form: the question with its options as rows (radio, or checkboxes when several
/// may be picked, and "Other…"), or a growing field for a free-text question, and Send; for an
/// approval, the tool or command with Deny and Allow. One primary button. The answer in progress
/// lives in `AgentPanelState`, tied to its question.
private struct QuestionForm: View {
    let task: BunnyTask
    let question: AgentQuestion
    private let state = AgentPanelState.shared

    private var draft: AgentPanelState.AnswerDraft { state.answer(for: task) }
    private var fieldFill: some ShapeStyle { BunnyTheme.surface(dark: .quaternary.opacity(0.5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if question.kind == .approval {
                approval
            } else {
                ForEach(question.items, id: \.key) { item in
                    itemView(item)
                }
            }
            HStack(spacing: 6) {
                Button("Stop") { AgentSupervisor.shared.stop(task) }
                    .buttonStyle(.bunny)
                Spacer(minLength: 0)
                if question.kind == .approval {
                    Button("Deny") { answer(AgentAnswer(selections: [:], approved: false)) }
                        .buttonStyle(.bunny)
                    Button("Allow") { answer(AgentAnswer(selections: [:], approved: true)) }
                        .buttonStyle(.bunnyProminent)
                } else {
                    Button("Send", action: send)
                        .buttonStyle(.bunnyProminent)
                        .disabled(!canSend)
                }
            }
        }
    }

    private func answer(_ answer: AgentAnswer) {
        AgentSupervisor.shared.answer(task, with: answer)
        state.answers[task.id] = nil
    }

    private func send() {
        guard canSend else { return }
        answer(AgentAnswer(selections: finalSelections(), approved: nil))
    }

    // MARK: Choices / freeform

    private func itemView(_ item: AgentQuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header = item.header, !header.isEmpty {
                Text(header)
                    .font(.system(size: 11))
                    .foregroundStyle(BunnyTheme.secondary)
            }
            Text(item.question)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            if item.options.isEmpty {
                TextField("Your answer", text: textBinding(item.key), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(2...8)
                    .padding(7)
                    .background(fieldFill, in: .rect(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 2) {
                    ForEach(item.options, id: \.label) { option in
                        optionRow(item, option)
                    }
                }
                if item.allowsOther {
                    TextField("Other…", text: textBinding(item.key))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .onSubmit(send)
                        .padding(7)
                        .background(fieldFill, in: .rect(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func optionRow(_ item: AgentQuestionItem, _ option: AgentQuestionOption) -> some View {
        let isSelected = (draft.selections[item.key] ?? []).contains(option.label)
        return Button {
            toggle(item, option)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isSelected
                      ? (item.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (item.multiSelect ? "square" : "circle"))
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(BunnyTheme.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.system(size: 12.5))
                    if let detail = option.detail, !detail.isEmpty {
                        Text(detail).font(.system(size: 11)).foregroundStyle(BunnyTheme.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(isSelected ? AnyShapeStyle(BunnyTheme.selection(dark: 0.2)) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canSend: Bool {
        let final = finalSelections()
        return question.items.allSatisfy { !(final[$0.key] ?? []).isEmpty }
    }

    private func finalSelections() -> [String: [String]] {
        let draft = draft
        var result: [String: [String]] = [:]
        for item in question.items {
            var values = draft.selections[item.key] ?? []
            let text = (draft.texts[item.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { values.append(text) }
            result[item.key] = values
        }
        return result
    }

    private func toggle(_ item: AgentQuestionItem, _ option: AgentQuestionOption) {
        var draft = draft
        var current = draft.selections[item.key] ?? []
        if let index = current.firstIndex(of: option.label) {
            current.remove(at: index)
        } else if item.multiSelect {
            current.append(option.label)
        } else {
            current = [option.label]
        }
        draft.selections[item.key] = current
        state.answers[task.id] = draft
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(get: { draft.texts[key] ?? "" }, set: { new in
            var draft = draft
            draft.texts[key] = new
            state.answers[task.id] = draft
        })
    }

    // MARK: Approval

    private var approval: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Allow this?")
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 3) {
                if let title = question.approvalTitle, !title.isEmpty {
                    Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                if let detail = question.approvalDetail, !detail.isEmpty {
                    Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(BunnyTheme.secondary)
                        .lineLimit(6)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(fieldFill, in: .rect(cornerRadius: 8, style: .continuous))
        }
    }
}
