import SwiftUI

struct SiriImportHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Save a webpage to your Import Inbox while browsing Safari, then review the recipe in Cauldron.")
                }
                Section("One-time setup in Shortcuts") {
                    Label("Create a shortcut named ‘Save this to Cauldron’.", systemImage: "1.circle")
                    Label("Open its Details and enable Receive What’s On Screen. Accept URLs as input.", systemImage: "2.circle")
                    Label("Add Cauldron’s Save Recipe from Webpage action. Set Recipe URL to Shortcut Input.", systemImage: "3.circle")
                }
                Section {
                    Text("With a recipe page open in Safari, say ‘Siri, save this to Cauldron.’ Shortcuts may ask for permission the first time.")
                    Text("The action queues the webpage for review; it doesn’t save an unchecked recipe to your library.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Link("Open Shortcuts", destination: URL(string: "shortcuts://")!)
                    Link("Apple’s onscreen shortcut guide", destination: URL(string: "https://support.apple.com/guide/shortcuts/apd350ce757a/ios")!)
                }
            }
            .navigationTitle("Import with Siri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}
