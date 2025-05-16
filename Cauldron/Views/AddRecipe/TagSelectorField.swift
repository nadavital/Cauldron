import SwiftUI

struct TagSelectorField: View {
    let label: String
    @Binding var selectedTagIDs: Set<String>
    @State private var showingTagSelectionSheet = false
    
    private let tagManager = AllRecipeTags.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Button {
                    showingTagSelectionSheet = true
                } label: {
                    HStack {
                        Text(selectedTagIDs.isEmpty ? "Select Tags" : "Edit Tags")
                        Image(systemName: "chevron.right")
                    }
                    .foregroundColor(.accentColor)
                }
            }
            
            // Display selected tags when there are some
            if !selectedTagIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tagManager.getTags(byIds: selectedTagIDs), id: \.id) { tag in
                            TagChip(tag: tag)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showingTagSelectionSheet) {
            TagSelectionView(selectedTagIDs: $selectedTagIDs)
        }
    }
}

// Tag chip component for display
struct TagChip: View {
    let tag: RecipeTag
    
    var body: some View {
        HStack(spacing: 4) {
            Image(tag.iconName)
                .resizable()
                .frame(width: 20, height: 20)
            Text(tag.name)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .foregroundColor(.accentColor)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var tags: Set<String> = ["cuisine_italian", "dietary_vegan"]
        var body: some View {
            Form {
                TagSelectorField(label: "Recipe Tags", selectedTagIDs: $tags)
            }
        }
    }
    return PreviewWrapper()
} 
