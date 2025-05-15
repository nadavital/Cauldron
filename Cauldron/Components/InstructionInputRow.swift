import SwiftUI

struct InstructionInputRow: View {
    @Binding var instruction: String
    let stepNumber: Int
    @Binding var isFocused: Bool
    
    @FocusState private var localFocus: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                // Step number in a styled circle
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [.accentColor.opacity(0.7), .accentColor]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 32, height: 32)
                        .shadow(color: .accentColor.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    Text("\(stepNumber)")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                }
                
                // Instruction text field
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        TextField("Step instruction", text: $instruction, axis: .vertical)
                            .lineLimit(1...10)
                            .focused($localFocus)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipped()
                    }
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading) // Prevents HStack from expanding wider than parent
            Divider()
                .padding(.leading, 60)
                .opacity(0.7)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        // Keep internal focus state in sync with external binding
        .onChange(of: localFocus) { newValue in
            DispatchQueue.main.async {
                isFocused = newValue
            }
        }
        // Remove external focus forcing on text change
        // .onChange(of: instruction) {
        //    DispatchQueue.main.async {
        //        isFocused = true
        //    }
        // }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var instruction1 = "Mix all dry ingredients in a large bowl"
        @State var instruction2 = ""
        @State var focused1 = false
        @State var focused2 = false
        
        var body: some View {
            VStack(spacing: 16) {
                InstructionInputRow(instruction: $instruction1, stepNumber: 1, isFocused: $focused1)
                InstructionInputRow(instruction: $instruction2, stepNumber: 2, isFocused: $focused2)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }
    
    return PreviewWrapper()
}

// MARK: - WrappingTextView
struct WrappingTextView: UIViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.returnKeyType = .done
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: WrappingTextView

        init(_ parent: WrappingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let original = textView.text ?? ""
            let clean = original.replacingOccurrences(of: "\n", with: " ")
            if clean != original {
                textView.text = clean
            }
            parent.text = clean
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.isFocused = false
                return false
            }
            return true
        }
    }
}
