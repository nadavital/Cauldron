import SwiftUI

struct RecipeInstructionsView: View {
    var instructions: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if instructions.isEmpty {
                Text("No instructions yet.")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                // No need for title - handled by parent section view
                
                // Instructions
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                    RecipeInstructionRow(index: index, instruction: instruction)
                }
            }
        }
        .accessibilityLabel("Recipe instructions with \(instructions.count) steps")
    }
}

#Preview {
    let instructions = [
        "Whisk together flour, sugar, baking powder, and salt in a large bowl.",
        "In a separate bowl, whisk together milk, egg, and melted butter.",
        "Pour the wet ingredients into the dry ingredients and mix until just combined (do not overmix; a few lumps are okay).",
        "Heat a lightly oiled griddle or frying pan over medium heat.",
        "Pour or scoop the batter onto the griddle, using approximately 1/4 cup for each pancake.",
        "Cook for 2-3 minutes per side, or until golden brown and cooked through.",
        "Serve warm with your favorite toppings."
    ]
    
    return RecipeInstructionsView(instructions: instructions)
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
        .padding()
}
