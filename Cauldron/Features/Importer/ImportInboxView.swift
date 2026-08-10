import SwiftUI

struct ImportInboxView: View {
    let store: RecipeImportInboxStore
    let onOpen: (RecipeImportJob) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var jobs: [RecipeImportJob] = []
    @State private var loadError: String?
    @State private var isPerformingBulkAction = false
    @State private var showingDiscardFailedConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if jobs.isEmpty {
                    AppStateView(
                        kind: .empty(systemImage: "tray"),
                        title: "Import Inbox Empty",
                        message: "Recipes shared to Cauldron will stay here until you save or discard them."
                    )
                } else {
                    List {
                        ForEach(jobs) { job in
                            Button {
                                onOpen(job)
                            } label: {
                                ImportInboxRow(job: job)
                            }
                            .buttonStyle(.plain)
                            .disabled(job.state == .processing || isPerformingBulkAction)
                            .swipeActions {
                                Button("Discard", role: .destructive) {
                                    Task { await discard(job) }
                                }
                                if job.state == .failed {
                                    Button("Retry") {
                                        Task { await retry(job) }
                                    }
                                    .tint(.cauldronOrange)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Import Inbox")
            .toolbar {
                if !failedJobs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu("Failed Imports", systemImage: "exclamationmark.triangle") {
                            Button("Retry All", systemImage: "arrow.clockwise") {
                                Task { await retryAllFailed() }
                            }
                            Button("Discard All", systemImage: "trash", role: .destructive) {
                                showingDiscardFailedConfirmation = true
                            }
                        }
                        .disabled(isPerformingBulkAction)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .alert("Unable to Load Imports", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(loadError ?? "Unknown error")
            }
            .confirmationDialog(
                "Discard all failed imports?",
                isPresented: $showingDiscardFailedConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard \(failedJobs.count) Failed Imports", role: .destructive) {
                    Task { await discardAllFailed() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes only imports that failed. Recipes already saved to your library are not affected.")
            }
        }
    }

    private var failedJobs: [RecipeImportJob] {
        jobs.filter { $0.state == .failed }
    }

    @MainActor
    private func reload() async {
        do {
            _ = try await store.recoverStaleProcessing(
                before: Date().addingTimeInterval(-10 * 60)
            )
            jobs = try await store.jobs().filter { $0.state != .completed }
        } catch {
            loadError = "Your imports are still on this device, but Cauldron couldn't read them right now."
        }
    }

    @MainActor
    private func discard(_ job: RecipeImportJob) async {
        do {
            try await store.remove(id: job.id)
            await reload()
        } catch {
            loadError = "Cauldron couldn't discard this import. Please try again."
        }
    }

    @MainActor
    private func retry(_ job: RecipeImportJob) async {
        do {
            _ = try await store.transition(id: job.id, to: .received)
            await reload()
        } catch {
            loadError = "Cauldron couldn't queue this import for retry."
        }
    }

    @MainActor
    private func retryAllFailed() async {
        guard !isPerformingBulkAction else { return }
        isPerformingBulkAction = true
        defer { isPerformingBulkAction = false }

        do {
            for job in failedJobs {
                _ = try await store.transition(id: job.id, to: .received)
            }
            await reload()
        } catch {
            await reload()
            loadError = "Some imports couldn't be queued for retry. The remaining failed imports are still in your inbox."
        }
    }

    @MainActor
    private func discardAllFailed() async {
        guard !isPerformingBulkAction else { return }
        isPerformingBulkAction = true
        defer { isPerformingBulkAction = false }

        do {
            for job in failedJobs {
                try await store.remove(id: job.id)
            }
            await reload()
        } catch {
            await reload()
            loadError = "Some failed imports couldn't be discarded. The remaining imports are still in your inbox."
        }
    }
}

private struct ImportInboxRow: View {
    let job: RecipeImportJob

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: iconName)
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(sourceTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Text(job.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: Theme.HitTarget.minimum)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sourceTitle), \(statusText)")
    }

    private var sourceTitle: String {
        switch job.source {
        case .url(let value):
            return URL(string: value)?.host ?? "Recipe Link"
        case .text:
            return "Recipe Text"
        case .prepared:
            return "Prepared Recipe"
        case .shareTransport(let item):
            if let data = item.preparedPayload,
               let payload = try? JSONDecoder().decode(PreparedShareRecipePayload.self, from: data) {
                return payload.title
            }
            if let value = item.urlString, let host = URL(string: value)?.host {
                return host
            }
            return "Shared Recipe"
        }
    }

    private var statusText: String {
        switch job.state {
        case .received: return job.attemptCount > 0 ? "Ready to retry" : "Waiting for review"
        case .processing: return "Importing"
        case .needsReview: return "Needs review"
        case .ready: return "Ready to save"
        case .failed: return "Import failed — swipe to retry"
        case .completed: return "Saved"
        }
    }

    private var iconName: String {
        switch job.state {
        case .received: return "tray.and.arrow.down"
        case .processing: return "arrow.trianglehead.2.clockwise"
        case .needsReview: return "doc.text.magnifyingglass"
        case .ready: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .completed: return "checkmark.seal"
        }
    }

    private var statusColor: Color {
        switch job.state {
        case .ready: return .green
        case .completed: return .green
        case .failed: return .red
        default: return .cauldronOrange
        }
    }
}
