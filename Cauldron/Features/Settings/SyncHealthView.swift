import SwiftUI

struct SyncHealthView: View {
    let viewModel: OperationQueueViewModel
    @State private var showingAcknowledgeConfirmation = false

    var body: some View {
        List {
            Section {
                Label(statusTitle, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
                if snapshot.pendingCount > 0 {
                    LabeledContent("Changes waiting", value: "\(snapshot.pendingCount)")
                }
                if let age = snapshot.oldestPendingAge {
                    LabeledContent("Oldest change") {
                        Text(Date.now.addingTimeInterval(-age), style: .relative)
                    }
                }
            } header: {
                Text("Sync Status")
            } footer: {
                Text("This shows changes waiting in Cauldron's durable upload queue. It does not certify that every iCloud record or image is current.")
            }

            if snapshot.failedCount > 0 {
                Section("Automatic Retry") {
                    Text("\(snapshot.failedCount) changes are waiting for Cauldron's automatic retry. Your local recipes remain available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.deadLetteredOperations.isEmpty {
                Section {
                    ForEach(viewModel.deadLetteredOperations, id: \.operationId) { deadLetter in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Protected change")
                                .font(.subheadline.weight(.medium))
                            Text(deadLetter.errorDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(deadLetter.capturedAt, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Button("Dismiss Notices", role: .destructive) {
                        showingAcknowledgeConfirmation = true
                    }
                    .accessibilityHint("Clears these notices without deleting local recipes or collections")
                } header: {
                    Text("Needs Attention")
                } footer: {
                    Text("Cauldron blocked these changes because they were malformed or belonged to a different iCloud account. Check that your local library looks right before dismissing the notices.")
                }
            }
        }
        .navigationTitle("Queued Uploads")
        .task {
            while !Task.isCancelled {
                await viewModel.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .refreshable { await viewModel.refresh() }
        .confirmationDialog(
            "Dismiss protected-change notices?",
            isPresented: $showingAcknowledgeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Dismiss Notices", role: .destructive) {
                viewModel.acknowledgeDeadLetteredOperations()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears only the diagnostic notices. It does not delete local recipes or collections.")
        }
    }

    private var snapshot: SyncHealthSnapshot { viewModel.healthSnapshot }

    private var statusTitle: String {
        switch snapshot.status {
        case .upToDate: return "No queued changes"
        case .waiting: return "Waiting to upload"
        case .syncing: return "Syncing"
        case .actionRequired: return "Some changes were protected"
        }
    }

    private var statusIcon: String {
        switch snapshot.status {
        case .upToDate: return "checkmark.icloud"
        case .waiting: return "clock.badge"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .actionRequired: return "exclamationmark.icloud"
        }
    }

    private var statusColor: Color {
        snapshot.status == .actionRequired ? .red : .cauldronOrange
    }
}
