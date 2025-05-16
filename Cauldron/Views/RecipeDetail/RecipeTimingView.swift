import SwiftUI

struct RecipeTimingView: View {
    var prepTime: Int
    var cookTime: Int
    var servings: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // Prep Time
            TimeInfoCard(
                title: "Prep Time",
                value: "\(prepTime)",
                icon: "clock.arrow.circlepath",
                iconColor: .blue,
                unit: "min"
            )
            
            // Cook Time
            TimeInfoCard(
                title: "Cook Time",
                value: "\(cookTime)",
                icon: "flame",
                iconColor: .orange,
                unit: "min"
            )
            
            // Servings
            TimeInfoCard(
                title: "Servings",
                value: "\(servings)",
                icon: "person.2",
                iconColor: .purple,
                unit: servings == 1 ? "serving" : "servings"
            )
        }
    }
}

// Reusable timing info component that matches TimeServingsInputRow styles
struct TimeInfoCard: View {
    var title: String
    var value: String
    var icon: String
    var iconColor: Color
    var unit: String
    
    var body: some View {
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
                
                // Value
                Text(value)
                    .font(.title2.bold())
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

#Preview {
    VStack(spacing: 20) {
        RecipeTimingView(prepTime: 15, cookTime: 30, servings: 4)
            .padding()
            .background(Color(.systemGroupedBackground))
        
        RecipeTimingView(prepTime: 5, cookTime: 0, servings: 1)
            .padding()
            .background(Color(.systemGroupedBackground))
    }
}