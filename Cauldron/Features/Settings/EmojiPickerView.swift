//
//  EmojiPickerView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/28/25.
//

import SwiftUI

/// Simple emoji picker using TextField with emoji keyboard
struct EmojiPickerView: View {
    @Binding var selectedEmoji: String?
    @Environment(\.dismiss) private var dismiss
    @State private var emojiInput = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Choose an Emoji")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Tap the field below and select any emoji from your keyboard")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("", text: $emojiInput)
                    .font(.system(size: 80))
                    .multilineTextAlignment(.center)
                    .focused($isTextFieldFocused)
                    .frame(height: 100)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: emojiInput) { oldValue, newValue in
                        // Only allow emoji characters
                        if let firstEmoji = newValue.first(where: { $0.isEmoji }) {
                            emojiInput = String(firstEmoji)
                        } else if !newValue.isEmpty {
                            // If user typed non-emoji characters, reject the input
                            emojiInput = oldValue
                        }
                    }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        if !emojiInput.isEmpty {
                            selectedEmoji = emojiInput
                        }
                        dismiss()
                    }
                    .disabled(emojiInput.isEmpty)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

#Preview {
    EmojiPickerView(selectedEmoji: .constant(nil))
}
