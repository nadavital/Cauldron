//
//  RecipeVisibilityPickerSheet.swift
//  Cauldron
//
//  Sheet for selecting recipe visibility
//

import SwiftUI

struct RecipeVisibilityPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var currentVisibility: RecipeVisibility
    @Binding var isChanging: Bool
    let onSave: (RecipeVisibility) async -> Void

    @State private var selectedVisibility: RecipeVisibility

    init(
        currentVisibility: Binding<RecipeVisibility>,
        isChanging: Binding<Bool>,
        onSave: @escaping (RecipeVisibility) async -> Void
    ) {
        self._currentVisibility = currentVisibility
        self._isChanging = isChanging
        self.onSave = onSave
        self._selectedVisibility = State(initialValue: currentVisibility.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Visibility", selection: $selectedVisibility) {
                        ForEach(RecipeVisibility.allCases, id: \.self) { visibility in
                            Label(visibility.displayName, systemImage: visibility.icon)
                                .tag(visibility)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    VStack(spacing: 8) {
                        Image(systemName: "eye")
                            .font(.system(size: 40))
                            .foregroundColor(.cauldronOrange)
                        Text("Choose who can see this recipe")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                    .textCase(nil)
                }

                Section {
                    Text(selectedVisibility.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Description")
                }
            }
            .navigationTitle("Recipe Visibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await onSave(selectedVisibility) }
                    } label: {
                        if isChanging {
                            ProgressView()
                        } else {
                            Label("Save", systemImage: "checkmark")
                        }
                    }
                    .disabled(isChanging || selectedVisibility == currentVisibility)
                }
            }
        }
    }
}
