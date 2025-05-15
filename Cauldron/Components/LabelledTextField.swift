import SwiftUI

struct LabelledTextField: View {
    let label: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var placeholder: String = ""
    var autocapitalization: TextInputAutocapitalization = .never
    var disableAutocorrection: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(autocapitalization)
                .disableAutocorrection(disableAutocorrection)
        }
    }
}

#Preview {
    // Create a @State var for the binding in the preview
    struct PreviewWrapper: View {
        @State var inputText: String = ""
        @State var numberInput: String = "123"

        var body: some View {
            Form {
                LabelledTextField(label: "Name", text: $inputText)
                LabelledTextField(label: "Quantity", text: $numberInput, keyboardType: .numberPad)
            }
        }
    }
    return PreviewWrapper()
}
