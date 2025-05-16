import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack {
            Spacer()
            
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 70))
                .foregroundColor(.secondary)
                .padding(.bottom, 16)
            
            Text("No Recipes Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, 8)
            
            Text("Tap the '+' button to add your first recipe.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 350)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding()
    }
}

#Preview {
    EmptyStateView()
} 