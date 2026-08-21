import SwiftUI

// MARK: - Functions View

struct FunctionsView: View {
    @Environment(ConnectionState.self) private var app
    @State private var searchText = ""
    @State private var showingLoadSheet = false
    @State private var libraryPendingDeletion: RedisFunctionLibrary?
    @State private var productionConfirmText = ""

    private var isProduction: Bool {
        app.selectedConnection?.environment == .production
    }
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
            }

            Divider()

            content
        }
        .task {
            if app.serverInfo.isEmpty { await app.loadServerInfo() }
            if app.supportsFunctions { await app.fetchFunctionLibraries() }
        }
        .sheet(isPresented: $showingLoadSheet) {
            LuaEditorView(mode: .create)
        }
        .confirmationDialog(
            "Delete library \"\(libraryPendingDeletion?.name ?? "")\"?",
            isPresented: Binding(
                get: { libraryPendingDeletion != nil && !isProduction },
                set: { isPresented in
                    if !isPresented { libraryPendingDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let library = libraryPendingDeletion {
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await app.deleteFunctionLibrary(name: library.name)
                        } catch {
                            app.functionsError = error.localizedDescription
                        }
                    }
                    libraryPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { libraryPendingDeletion = nil }
        } message: {
            if let nodes = libraryPendingDeletion?.nodes, !nodes.isEmpty {
                Text(
                    "This will delete the library from \(nodes.count) primary node(s). This action cannot be undone."
                )
            } else {
                Text("This action cannot be undone.")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { libraryPendingDeletion != nil && isProduction },
                set: { isPresented in
                    if !isPresented {
                        libraryPendingDeletion = nil
                        productionConfirmText = ""
                    }
                }
            )
        ) {
            if let library = libraryPendingDeletion {
                ProductionConfirmView(
                    title: "Delete library \"\(library.name)\"?",
                    message: "This will permanently delete the library. This action cannot be undone.",
                    confirmText: "DELETE",
                    input: $productionConfirmText,
                    onConfirm: {
                        Task {
                            do {
                                try await app.deleteFunctionLibrary(name: library.name)
                            } catch {
                                app.functionsError = error.localizedDescription
                            }
                        }
                        libraryPendingDeletion = nil
                        productionConfirmText = ""
                    },
                    onCancel: {
                        libraryPendingDeletion = nil
                        productionConfirmText = ""
                    }
                )
                .presentationSizing(.form)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        @Bindable var app = app
        return HStack(spacing: AppSpacing.medium) {
            FilterField("Filter libraries", text: $searchText)
                .frame(maxWidth: .infinity)

            if app.isLoadingFunctions {
                ProgressView()
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
            LoadingState(message: "Loading functions...")
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
        return VStack(spacing: 0) {
            Group {
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
                            libraryRow(library)
                                .fullWidthListRowSeparator()
                                .tag(library.name)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        libraryPendingDeletion = library
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }

            Divider()

            WorkspaceFooterBar {
                StatusFooterView(countText: footerText)
                Spacer()
            }
        }
    }

    private func libraryRow(_ library: RedisFunctionLibrary) -> some View {
        HStack(spacing: AppSpacing.small) {
            Text(library.engine)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: AppSize.typeBadgeWidth, alignment: .center)
                .padding(.vertical, AppSpacing.xxSmall)
                .background(AppColor.subtleBackground)
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
