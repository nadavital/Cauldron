import SwiftUI

struct RecipeInstructionRow: View {
    var index: Int
    var instruction: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Step number in circle - styled consistently
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                
                Text("\(index + 1)")
                    .font(.callout.bold())
                    .foregroundColor(Color.accentColor)
            }
            
            // Instruction text with improved styling
            Text(instruction)
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index + 1): \(instruction)")
    }
}

// Preview
#Preview {
    VStack(spacing: 16) {
        RecipeInstructionRow(
            index: 0, 
            instruction: "Whisk together flour, sugar, baking powder, and salt in a large bowl."
        )
        
        Divider()
        
        RecipeInstructionRow(
            index: 1, 
            instruction: "In a separate bowl, whisk together milk, egg, and melted butter."
        )
        
        Divider()
        
        RecipeInstructionRow(
            index: 2, 
            instruction: "Pour the wet ingredients into the dry ingredients and mix until just combined (do not overmix; a few lumps are okay)."
        )
    }
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(12)
    .padding()
}