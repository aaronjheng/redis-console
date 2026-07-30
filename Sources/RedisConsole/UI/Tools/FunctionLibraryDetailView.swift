import SwiftUI

// MARK: - Function Library Detail View

struct FunctionLibraryDetailView: View {
    @Environment(ConnectionState.self) private var app
    let library: RedisFunctionLibrary

    @State private var showingDeleteConfirm = false
    @State private var showingEditSheet = false
    @State private var showingCallSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                SelectableText(
                    text: library.code,
                    font: .monospacedSystemFont(ofSize: NSFont.systemFont(ofSize: 13).pointSize, weight: .regular)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.large)
            }
            .onTapGesture(count: 2) {
                showingEditSheet = true
            }
            .overlay(alignment: .topTrailing) {
                Button("Edit Source", systemImage: "pencil") {
                    showingEditSheet = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Edit library source")
                .padding(AppSpacing.large)
            }
        }
        .frame(maxHeight: .infinity)
        .sheet(isPresented: $showingEditSheet) {
            LuaEditorView(mode: .edit(library))
        }
        .sheet(isPresented: $showingCallSheet) {
            FunctionCallView(library: library)
        }
        .confirmationDialog(
            "Delete library \"\(library.name)\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await app.deleteFunctionLibrary(name: library.name)
                    } catch {
                        app.functionsError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let nodes = library.nodes, !nodes.isEmpty {
                Text(
                    "This will delete the library from \(nodes.count) primary node(s). This action cannot be undone."
                )
            } else {
                Text("This action cannot be undone.")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(spacing: AppSpacing.small) {
                Badge(text: library.engine, isLoading: library.engine.isEmpty)
                Text(library.name)
                    .font(.title3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button {
                    showingCallSheet = true
                } label: {
                    Label("Call", systemImage: "play")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(library.functions.isEmpty)
                .help("Run a function (FCALL)")
                DeleteIconButton(action: { showingDeleteConfirm = true }, helpText: "Delete library")
            }
            HStack(spacing: AppSpacing.medium - AppSpacing.xxSmall) {
                HStack(spacing: AppSpacing.xxSmall) {
                    Image(systemName: "number")
                    Text("\(library.functionCount) function\(library.functionCount == 1 ? "" : "s")")
                }
                .foregroundStyle(.secondary)
                if library.isReadOnly {
                    HStack(spacing: AppSpacing.xxSmall) {
                        Image(systemName: "lock.fill")
                        Text("Read-only")
                    }
                    .foregroundStyle(AppColor.success)
                }
                if let nodes = library.nodes, !nodes.isEmpty {
                    HStack(spacing: AppSpacing.xSmall) {
                        Image(systemName: "server.rack")
                        Text(nodes.map(\.address).joined(separator: ", "))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.small)
    }
}
