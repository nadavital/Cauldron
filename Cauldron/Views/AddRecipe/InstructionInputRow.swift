import SwiftUI

struct InstructionInputRow: View {
    @Binding var instruction: String
    let stepNumber: Int
    @Binding var isFocused: Bool
    
    // Local focus state that syncs with parent
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
                
                // Instruction text field - use native TextEditor
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $instruction)
                        .frame(minHeight: 40, maxHeight: instruction.isEmpty ? 40 : .infinity)
                        .fixedSize(horizontal: false, vertical: instruction.isEmpty)
                        .focused($localFocus)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    
                    // Placeholder text
                    if instruction.isEmpty {
                        Text("Step instruction")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .padding(.leading, 60)
                .opacity(0.7)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .onChange(of: isFocused) { newValue in
            localFocus = newValue
        }
        .onChange(of: localFocus) { newValue in
            isFocused = newValue
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
