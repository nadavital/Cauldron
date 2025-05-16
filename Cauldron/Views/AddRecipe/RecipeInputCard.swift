import SwiftUI

struct RecipeInputCard: View {
    var title: String
    var systemImage: String
    var content: () -> AnyView
    
    init(title: String, systemImage: String, @ViewBuilder content: @escaping () -> some View) {
        self.title = title
        self.systemImage = systemImage
        self.content = { AnyView(content()) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.bottom, 4)
            
            // Content
            content()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            RecipeInputCard(title: "Basic Info", systemImage: "info.circle") {
                Text("Sample content goes here")
            }
            
            RecipeInputCard(title: "Ingredients", systemImage: "list.bullet") {
                Text("Ingredients content")
            }
        }
        .padding()
    }
} 