import SwiftUI

struct DeleteButton: View {
    var recipe: Recipe
    var deleteAction: (UUID) -> Void
    
    var body: some View {
        Button {
            withAnimation {
                deleteAction(recipe.id)
            }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.title2)
                .foregroundColor(.red)
                .padding(6)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
        }
        .padding([.top, .trailing], 6)
        .transition(.scale)
    }
}

#Preview {
    ZStack(alignment: .topTrailing) {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 200, height: 150)
            .cornerRadius(12)
        
        DeleteButton(
            recipe: Recipe(
                name: "Sample Recipe",
                ingredients: [],
                instructions: [],
                prepTime: 10,
                cookTime: 20,
                servings: 4,
                imageData: nil,
                tags: []
            ),
            deleteAction: { _ in print("Delete tapped") }
        )
    }
    .padding()
} 