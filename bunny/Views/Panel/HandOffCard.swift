import AppKit
import SwiftData
import SwiftUI

/// The Hand off options card (v3 spec §7 "Hand off"), opened by the arrow next to the note side's
/// Hand off. It floats above the footer inside the note side and stays open while choices are made:
/// Folder, Agent, Model and Effort, each a native menu popped on demand. Every choice is stored on
/// the note at once, so both Hand off buttons use it afterwards. Esc or a click outside closes it
/// without starting; its own Hand off starts the run and closes it.
struct HandOffCard: View {
    let task: BunnyTask
    @Environment(PanelCoordinator.self) private var coordinator
    @Query private var shelfItems: [ShelfItem]
    @State private var folderNote: String?
    /// The Custom… model field shows.
    @State private var editingCustomModel = false
    private let enablement = AgentEnablement.shared
    private let codexModels = CodexModelStore.shared

    init(task: BunnyTask) {
        self.task = task
        let taskID = task.id
        _shelfItems = Query(filter: #Predicate<ShelfItem> { $0.taskID == taskID }, sort: \ShelfItem.sortOrder)
    }

    private var settings: RunSettings { AgentSettings.runSettings(for: task, newRun: true) }
    private var harness: AgentHarness { settings.harness }
    private var folder: WorkingDirectoryResolver.Resolution {
        AgentSettings.folder(choice: task.agentFolderChoice, shelf: AgentSettings.shelfEntries(shelfItems), harness: harness)
    }
    /// The note's own model/effort, when they were chosen for `harness` (nil = the default).
    private var modelOverride: String? { task.harness == harness ? AgentRunnerText.nonEmpty(task.agentModel) : nil }
    private var effortOverride: String? { task.harness == harness ? AgentRunnerText.nonEmpty(task.agentEffort) : nil }
    private var hasChoices: Bool {
        task.agentHarnessChosen || task.agentModel != nil || task.agentEffort != nil || task.agentFolderChoice != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Folder", value: WorkingDirectoryResolver.name(of: folder), caption: folderCaption, help: folder.cwd,
                menu: folderMenu)
            if let folderNote {
                Text(folderNote)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 4)
            }
            row("Agent", value: harness.displayName, logo: harness, menu: agentMenu)
            row("Model", value: AgentSettings.modelName(settings), menu: modelMenu)
            if editingCustomModel || isCustomModel {
                TextField("Model id", text: customModelText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
            row("Effort", value: AgentSettings.effortName(settings), menu: effortMenu)
            HStack {
                Button("Reset to defaults") { reset() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(BunnyTheme.secondary)
                    .disabled(!hasChoices)
                    .opacity(hasChoices ? 1 : 0.5)
                Spacer()
                Button {
                    coordinator.handOffCardTaskID = nil
                    AgentSupervisor.shared.start(task, harness: nil)
                } label: {
                    Text("Hand off")
                }
                .buttonStyle(.bunnyProminent.lively())
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background {
            // The shadow belongs to the card's shape only, not to the text in it.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BunnyTheme.background())
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .onAppear { if enablement.isEnabled(.codex) { codexModels.loadIfNeeded() } }
    }

    // MARK: - Rows

    private func row(_ title: String, value: String, caption: String? = nil, help: String? = nil,
                     logo: AgentHarness? = nil, menu: @escaping () -> [PopUpMenu.Item?]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5))
                if let caption {
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(BunnyTheme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            PopUpButton(value: value, logo: logo, menu: menu)
                .help(help ?? "")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var folderCaption: String? {
        switch folder.source {
        case .attachedFolder: return "from the attached folder"
        case .attachedFile: return "from an attached file's folder"
        case .chosen, .settings: return folder.isBunnyFolder ? "no project needed" : AgentSettings.abbreviated(folder.cwd)
        }
    }

    // MARK: - Menus

    private func folderMenu() -> [PopUpMenu.Item?] {
        var items: [PopUpMenu.Item?] = AgentSettings.recentFolders.map { path in
            PopUpMenu.Item(title: WorkingDirectoryResolver.name(ofPath: path), subtitle: AgentSettings.abbreviated(path),
                           checked: !folder.isBunnyFolder && WorkingDirectoryResolver.key(folder.cwd) == path) {
                choose(folder: path)
            }
        }
        if !items.isEmpty { items.append(nil) }
        items.append(PopUpMenu.Item(title: "Bunny folder", subtitle: "no project needed", checked: folder.isBunnyFolder) {
            choose(folder: WorkingDirectoryResolver.bunnyFolderChoice)
        })
        items.append(nil)
        items.append(PopUpMenu.Item(title: "Choose Folder…") { chooseFolder() })
        return items
    }

    private func agentMenu() -> [PopUpMenu.Item?] {
        enablement.available.map { candidate in
            PopUpMenu.Item(title: candidate.displayName, checked: candidate == harness) {
                task.agentHarness = candidate.rawValue
                task.agentHarnessChosen = true
                // Model/effort belong to the agent they were chosen for.
                task.agentModel = nil
                task.agentEffort = nil
                editingCustomModel = false
                if candidate == .codex { codexModels.loadIfNeeded() }
            }
        }
    }

    private func modelMenu() -> [PopUpMenu.Item?] {
        let current = modelOverride
        let settingsModel = AgentSettings.model(for: harness)
        let defaultName = AgentModelOptions.defaultModelName(for: harness, settingsModel: settingsModel,
                                                             codexModels: codexModels.models,
                                                             lastClaudeModel: AgentSettings.lastClaudeModel)
        var items: [PopUpMenu.Item?] = [
            PopUpMenu.Item(title: defaultName.map { "Default (\($0))" } ?? "Default", checked: current == nil && !editingCustomModel) {
                choose(model: .some(nil))
            },
            nil,
        ]
        let known: [(id: String, name: String)]
        switch harness {
        case .claudeCode:
            known = AgentModelOptions.claudeModelAliases.map { ($0, AgentModelOptions.displayName($0)) }
        case .codex:
            known = codexModels.models.map { ($0.id, $0.displayName) }
            if known.isEmpty {
                items.append(PopUpMenu.Item(title: codexModels.isLoading ? "Loading models…" : "Model list unavailable", enabled: false))
            }
        }
        items += known.map { model in
            PopUpMenu.Item(title: model.name, checked: current == model.id) { choose(model: model.id) }
        }
        items.append(nil)
        items.append(PopUpMenu.Item(title: "Custom…", checked: isCustomModel || editingCustomModel) {
            editingCustomModel = true
        })
        return items
    }

    private func effortMenu() -> [PopUpMenu.Item?] {
        let current = effortOverride
        let defaultName = AgentModelOptions.defaultEffortName(for: harness, settingsEffort: AgentSettings.effort(for: harness),
                                                              modelID: settings.model, codexModels: codexModels.models)
        let options = AgentModelOptions.efforts(for: harness, modelID: settings.model, codexModels: codexModels.models)
        return [
            PopUpMenu.Item(title: defaultName.map { "Default (\($0))" } ?? "Default", checked: current == nil) {
                choose(effort: .some(nil))
            },
            nil,
        ] + options.map { effort in
            PopUpMenu.Item(title: AgentModelOptions.displayName(effort), checked: current == effort) { choose(effort: effort) }
        }
    }

    // MARK: - Choices

    /// A model the menus don't list (typed under Custom…).
    private var isCustomModel: Bool {
        guard let current = modelOverride else { return false }
        switch harness {
        case .claudeCode: return !AgentModelOptions.claudeModelAliases.contains(current)
        case .codex: return !codexModels.models.isEmpty && !codexModels.models.contains { $0.id == current }
        }
    }

    private var customModelText: Binding<String> {
        Binding(get: { modelOverride ?? "" }, set: { choose(model: .some(AgentRunnerText.nonEmpty($0))) })
    }

    /// Binds a model/effort choice to the card's agent, so it never applies to another one.
    private func choose(model: String?? = .none, effort: String?? = .none) {
        task.agentHarness = harness.rawValue
        task.agentHarnessChosen = true
        if case let .some(model) = model {
            task.agentModel = model
            editingCustomModel = false
        }
        if case let .some(effort) = effort { task.agentEffort = effort }
    }

    private func choose(folder choice: String) {
        task.agentFolderChoice = choice
        folderNote = nil
    }

    private func chooseFolder() {
        coordinator.pickFiles(foldersOnly: true) { urls in
            guard let url = urls.first else { return }
            if AgentSettings.isHome(url.path) {
                folderNote = "The home folder can't be used: an agent could change everything in it."
            } else {
                choose(folder: url.path)
            }
        }
    }

    private func reset() {
        task.agentHarness = nil
        task.agentHarnessChosen = false
        task.agentModel = nil
        task.agentEffort = nil
        task.agentFolderChoice = nil
        editingCustomModel = false
        folderNote = nil
    }
}
