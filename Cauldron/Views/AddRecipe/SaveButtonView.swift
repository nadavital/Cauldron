import SwiftUI

struct SaveButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Save Recipe")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .padding(.top, 20)
    }
}

#Preview {
    SaveButtonView(action: {})
        .padding()
}