import SwiftUI

/// The Settings window: a sidebar with search and the six pages, and the selected page as a column
/// of cards. Pages and rows come from `SettingsCatalog`.
struct SettingsView: View {
    @Environment(SettingsModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar()
                .frame(width: SettingsMetrics.sidebarWidth)
            Divider().ignoresSafeArea()
            detail
        }
        .frame(minWidth: 680, minHeight: 420)
        // Settings' pop-up buttons drop their menus down below themselves.
        .environment(\.popUpMenusDropDown, true)
        .background(Rectangle().fill(BunnyTheme.background()).ignoresSafeArea())
    }

    private var detail: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.page.title)
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.leading, SettingsMetrics.rowPadding)
                        .padding(.bottom, 2)
                    switch model.page {
                    case .general: GeneralSettingsPage()
                    case .appearance: AppearanceSettingsPage()
                    case .notes: NotesSettingsPage()
                    case .agents: AgentsSettingsPage()
                    case .data: DataSettingsPage()
                    case .about: AboutSettingsPage()
                    }
                }
                .frame(maxWidth: SettingsMetrics.contentWidth, alignment: .leading)
                .padding(SettingsMetrics.padding)
                .frame(maxWidth: .infinity)
                .id(model.page)
            }
            .onChange(of: model.highlighted) { _, row in
                guard let row else { return }
                // After the page (and an unfolded Advanced part) has been laid out.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(row, anchor: .center) }
                }
            }
        }
    }
}

/// Search field on top; under it the pages, or while searching the pages that match with their
/// matching rows.
private struct SettingsSidebar: View {
    @Environment(SettingsModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = SettingsCatalog.search(model.query)
        let searching = !model.query.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(spacing: 10) {
            searchField(results)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !searching {
                        ForEach(SettingsCatalog.Page.allCases) { pageButton($0) }
                    } else if results.isEmpty {
                        Text("No results")
                            .font(.callout)
                            .foregroundStyle(BunnyTheme.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                    } else {
                        ForEach(results, id: \.page) { result in
                            pageButton(result.page)
                            ForEach(result.rows) { row in rowButton(row) }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Rectangle().fill(BunnyTheme.surface(dark: Color.primary.opacity(0.035))).ignoresSafeArea())
        .background { shortcuts }
        .onChange(of: model.searchFocusRequests) { searchFocused = true }
    }

    private func searchField(_ results: [SettingsCatalog.Result]) -> some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(BunnyTheme.secondary)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // Return opens the first match.
                .onSubmit { if let row = results.first?.rows.first { model.reveal(row) } else if let page = results.first?.page { model.page = page } }
                // Esc clears the search; with nothing to clear it leaves the field.
                .onExitCommand {
                    if model.query.isEmpty { NSApp.keyWindow?.makeFirstResponder(nil) } else { model.query = "" }
                }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BunnyTheme.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(BunnyTheme.deepSurface(dark: Color.primary.opacity(0.07)), in: .rect(cornerRadius: 8, style: .continuous))
    }

    private func pageButton(_ page: SettingsCatalog.Page) -> some View {
        let selected = model.page == page
        return Button { model.page = page } label: {
            HStack(spacing: 8) {
                Image(systemName: page.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)
                Text(page.title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(selected ? AnyShapeStyle(BunnyTheme.selection(dark: 0.16)) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func rowButton(_ row: SettingsCatalog.Row) -> some View {
        Button { model.reveal(row) } label: {
            Text(row.title)
                .font(.callout)
                .foregroundStyle(BunnyTheme.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 36)
                .padding(.trailing, 8)
                .padding(.vertical, 4)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(row.title)
    }

    /// ⌘F focuses the search field; Esc clears the search when the field does not have focus
    /// (with focus, the field's own Esc does).
    private var shortcuts: some View {
        Group {
            Button("") { model.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { model.query = "" }
                .keyboardShortcut(.cancelAction)
                .disabled(model.query.isEmpty)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
