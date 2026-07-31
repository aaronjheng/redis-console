import SwiftUI

// MARK: - Functions View

struct FunctionsView: View {
    @Environment(ConnectionState.self) private var app
    @State private var searchText = ""
    @State private var showingLoadSheet = false
    private var isClusterMode: Bool {
        app.selectedConnection?.mode == .cluster || !app.clusterNodes.isEmpty
    }

    private var filteredLibraries: [RedisFunctionLibrary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return app.functionLibraries }
        return app.functionLibraries.filter { $0.name.lowercased().contains(query) }
    }

    /// The currently selected library, freshly resolved against the latest fetch
    /// so the detail view always reflects reloaded data.
    private var displayedLibrary: RedisFunctionLibrary? {
        guard let selected = app.selectedFunctionLibrary else { return nil }
        return app.functionLibraries.first { $0.name == selected.name }
    }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            header

            if let error = app.functionsError {
                ErrorBanner(message: error, dismissAction: { app.functionsError = nil })
                Divider()
            }

            Divider()

            content

            Divider()
            WorkspaceFooterBar {
                StatusFooterView(countText: footerText)
                Spacer()
            }
        }
        .task {
            if app.serverInfo.isEmpty { await app.loadServerInfo() }
            if app.supportsFunctions { await app.fetchFunctionLibraries() }
        }
        .sheet(isPresented: $showingLoadSheet) {
            LuaEditorView(mode: .create)
        }
    }

    // MARK: Header

    private var header: some View {
        @Bindable var app = app
        return HStack(spacing: AppSpacing.medium) {
            ZStack(alignment: .trailing) {
                TextField("Filter libraries", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        searchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
                }
            }
            .frame(maxWidth: 320)

            Spacer()

            if app.isLoadingFunctions {
                ProgressView()
                    .scaleEffect(0.7)
                    .controlSize(.small)
            }

            Button {
                Task { await app.fetchFunctionLibraries() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(app.isLoadingFunctions || !app.supportsFunctions)

            Button {
                showingLoadSheet = true
            } label: {
                Label("Load", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!app.supportsFunctions)
        }
        .panelToolbar(horizontalPadding: AppSpacing.small)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if app.activeClient?.isConnected != true {
            emptyState("Not connected", "Connect to a Redis server to manage functions")
        } else if !app.supportsFunctions {
            ContentUnavailableView(
                "Redis 7.0+ required",
                systemImage: "curlybraces",
                description: Text("Redis Functions are available in Redis 7.0 and later.")
            )
        } else if app.isLoadingFunctions && app.functionLibraries.isEmpty {
            Spacer()
            ProgressView("Loading functions...")
                .controlSize(.small)
            Spacer()
        } else {
            PersistentSplitView(
                autosaveName: "com.redisconsole.functionsSplit",
                leftMinWidth: 220,
                rightMinWidth: 320
            ) {
                libraryList
            } right: {
                if let library = displayedLibrary {
                    FunctionLibraryDetailView(library: library)
                } else {
                    Spacer()
                    ContentUnavailableView(
                        "No library selected",
                        systemImage: "curlybraces",
                        description: Text("Select a library to view its functions and source code.")
                    )
                    Spacer()
                }
            }
        }
    }

    // MARK: Library list

    private var libraryList: some View {
        @Bindable var app = app
        return Group {
            if filteredLibraries.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No libraries",
                    systemImage: "curlybraces",
                    description: Text("Load a function library to get started.")
                )
                Spacer()
            } else {
                List(
                    selection: Binding<String?>(
                        get: { app.selectedFunctionLibrary?.name },
                        set: { selectedName in
                            app.selectedFunctionLibrary = selectedName.flatMap { name in
                                app.functionLibraries.first { $0.name == name }
                            }
                        }
                    )
                ) {
                    ForEach(filteredLibraries) { library in
                        libraryRow(library).tag(library.name)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func libraryRow(_ library: RedisFunctionLibrary) -> some View {
        HStack(spacing: AppSpacing.small) {
            Text(library.engine)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 48, alignment: .center)
                .padding(.vertical, AppSpacing.xxSmall)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            Text(library.name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, AppSpacing.small)
        .help(library.name)
    }

    // MARK: Helpers

    private var footerText: String {
        let total = app.functionLibraries.count
        let filtered = filteredLibraries.count
        if isClusterMode {
            let primaryCount = app.clusterNodes.filter { $0.role == .primary }.count
            if primaryCount > 0 {
                return "\(total) libraries \u{00B7} \(primaryCount) primaries"
            }
        }
        if searchText.isEmpty || filtered == total {
            return "\(total) libraries"
        }
        return "\(filtered) of \(total) libraries"
    }

    private func emptyState(_ title: String, _ description: String) -> some View {
        VStack {
            Spacer()
            ContentUnavailableView(title, systemImage: "curlybraces", description: Text(description))
            Spacer()
        }
    }
}
