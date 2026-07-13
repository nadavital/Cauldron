import SwiftUI

struct SyncHealthView: View {
    let viewModel: OperationQueueViewModel

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
        }
        .navigationTitle("Queued Uploads")
        .task {
            while !Task.isCancelled {
                viewModel.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .refreshable { viewModel.refresh() }
    }

    private var snapshot: SyncHealthSnapshot { viewModel.healthSnapshot }

    private var statusTitle: String {
        switch snapshot.status {
        case .upToDate: return "No queued changes"
        case .waiting: return "Waiting to upload"
        case .syncing: return "Syncing"
        case .actionRequired: return "Some changes need attention"
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
