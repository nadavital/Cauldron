import SwiftUI

struct InstructionInputRow: View {
    @Binding var instruction: String
    let stepNumber: Int
    @Binding var isFocused: Bool
    
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
                    // Use UIKit text view for both iOS 16+ and earlier
                    InstructionTextView(text: $instruction, isFocused: $isFocused)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1) // Give this column layout priority
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
        // Only add a tap gesture to non-text areas
        .contentShape(Rectangle())
        .onTapGesture {
            // Only dismiss keyboard if we're already focused and tapping outside the text
            if isFocused {
                endEditing()
            }
        }
        // Use simultaneous gesture with a high minimum distance to avoid interfering with scrolling
        .simultaneousGesture(
            DragGesture(minimumDistance: 60) // Higher minimum distance to avoid scroll conflicts
                .onChanged { _ in
                    // Only dismiss if focused - this helps avoid conflicts with scrolling
                    if isFocused {
                        endEditing()
                    }
                }
        )
    }
    
    // Helper function to hide keyboard and update focus state
    private func endEditing() {
        // First set our bound focus state to false
        isFocused = false
        
        // Then use UIKit to ensure the keyboard is dismissed
        DispatchQueue.main.async {
            let keyWindow = UIApplication.shared.connectedScenes
                .filter({$0.activationState == .foregroundActive})
                .compactMap({$0 as? UIWindowScene})
                .first?.windows
                .filter({$0.isKeyWindow}).first
            
            keyWindow?.endEditing(true)
        }
    }
}

// MARK: - InstructionTextView
struct InstructionTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    
    // Add intrinsicContentSize for better sizing
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width * 0.7
        let newSize = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: newSize.height)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        
        // Configure scrolling behavior - better defaults for scrolling
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true // Helps with scrolling feedback
        tv.showsHorizontalScrollIndicator = false
        tv.showsVerticalScrollIndicator = true
        
        // Text container setup for proper wrapping
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.textContainer.maximumNumberOfLines = 0
        tv.textAlignment = .left
        
        // Auto-sizing and constraints setup
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Configure appearance
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.returnKeyType = .done
        
        // Proper insets to ensure text doesn't run to the edge
        tv.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        // For smoother text entry and scrolling
        tv.autocorrectionType = .yes
        tv.keyboardDismissMode = .interactive
        
        // Ensure scrolling works properly during editing
        tv.isUserInteractionEnabled = true
        
        // Set placeholder if text is empty
        if text.isEmpty {
            tv.text = "Step instruction"
            tv.textColor = UIColor.placeholderText
        } else {
            tv.text = text
            tv.textColor = UIColor.label
        }
        
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only update text if it doesn't match and we're not currently editing
        if uiView.text != text && !context.coordinator.isEditing {
            uiView.text = text
            
            // Handle placeholder
            if text.isEmpty {
                uiView.text = "Step instruction"
                uiView.textColor = UIColor.placeholderText
            } else {
                uiView.textColor = UIColor.label
            }
        }
        
        // Only handle focus when isFocused changes from the outside
        // Let the delegate methods handle changes initiated from UIKit
        if isFocused && !uiView.isFirstResponder && !context.coordinator.isEditing {
            uiView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: InstructionTextView
        var isEditing = false

        init(_ parent: InstructionTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // Update the bound text
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            
            // Clear placeholder if needed
            if textView.textColor == UIColor.placeholderText {
                textView.text = ""
                textView.textColor = UIColor.label
            }
            
            // Update focus state directly without async dispatch to avoid conflicts
            parent.isFocused = true
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            
            // Set placeholder if empty
            if textView.text.isEmpty {
                textView.text = "Step instruction"
                textView.textColor = UIColor.placeholderText
            }
            
            // Update focus state directly without async dispatch to avoid conflicts
            parent.isFocused = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                // Dismiss keyboard properly
                parent.isFocused = false
                textView.resignFirstResponder()
                
                // Force end editing on the window level
                UIApplication.shared.connectedScenes
                    .filter({$0.activationState == .foregroundActive})
                    .compactMap({$0 as? UIWindowScene})
                    .first?.windows
                    .filter({$0.isKeyWindow}).first?
                    .endEditing(true)
                
                return false
            }
            return true
        }
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
