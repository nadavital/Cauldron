import SwiftUI
import UIKit

struct TimeServingsInputRow: View {
    @Binding var prepTime: String
    @Binding var cookTime: String
    @Binding var servings: String
    
    // Create a FocusState to track keyboard focus
    @FocusState private var focusField: Field?
    
    // Define fields that can have focus
    enum Field {
        case prep, cook, servings
    }
    
    var body: some View {
        Group {
            HStack(spacing: 16) {
                // Prep Time
                timeInputCard(
                    title: "Prep Time",
                    value: $prepTime,
                    icon: "clock.arrow.circlepath",
                    iconColor: .blue,
                    unit: "min",
                    placeholder: "15",
                    field: .prep
                )
                
                // Cook Time
                timeInputCard(
                    title: "Cook Time",
                    value: $cookTime,
                    icon: "flame",
                    iconColor: .orange,
                    unit: "min",
                    placeholder: "30",
                    field: .cook
                )
                
                // Servings
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                    
                    VStack(spacing: 10) {
                        // Header with icon
                        Label {
                            Text("Servings")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        } icon: {
                            Image(systemName: "person.2")
                                .foregroundColor(.purple)
                        }
                        
                        // Text field with placeholder
                        ZStack(alignment: .center) {
                            if servings.isEmpty {
                                Text("4")
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .font(.title2.bold())
                            }
                            TextField("", text: $servings)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.title2.bold())
                                .submitLabel(.done)
                                .focused($focusField, equals: .servings)
                                .onSubmit {
                                    focusField = nil
                                }
                        }
                        .frame(height: 36)
                        
                        // Dynamic unit label
                        Text(servingText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 100)
            }
        }
        .toolbar {
            // Only show Done button when a number-pad field is focused
            if focusField == .prep || focusField == .cook || focusField == .servings {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusField = nil
                    }
                }
            }
        }
    }
    
    private var servingText: String {
        if servings.isEmpty {
            return "servings"
        }
        let count = Int(servings) ?? 0
        return count == 1 ? "serving" : "servings"
    }
    
    private func timeInputCard(title: String, value: Binding<String>, icon: String, iconColor: Color, unit: String, placeholder: String, field: Field) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
            
            VStack(spacing: 10) {
                // Header with icon
                Label {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                }
                
                // Text field with placeholder
                ZStack(alignment: .center) {
                    if value.wrappedValue.isEmpty {
                        Text(placeholder)
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.title2.bold())
                    }
                    TextField("", text: value)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.title2.bold())
                        .submitLabel(.done)
                        .focused($focusField, equals: field)
                        .onSubmit {
                            focusField = nil
                        }
                }
                .frame(height: 36)
                
                // Unit label
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 100)
        }
    }

// Extension to add a placeholder to TextField
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var prep = ""
        @State var cook = ""
        @State var servings = ""
        
        var body: some View {
            VStack {
                TimeServingsInputRow(prepTime: $prep, cookTime: $cook, servings: $servings)
                    .padding()
                
                // With values
                TimeServingsInputRow(prepTime: .constant("25"), cookTime: .constant("45"), servings: .constant("2"))
                    .padding()
                
                // With singular
                TimeServingsInputRow(prepTime: .constant("10"), cookTime: .constant("20"), servings: .constant("1"))
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    return PreviewWrapper()
}
