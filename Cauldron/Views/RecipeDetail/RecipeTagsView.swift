import SwiftUI

struct RecipeTagsView: View {
    var tagIDs: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // No need for the title - it's now in the section view
            FlowLayout(spacing: 10) {
                ForEach(Array(tagIDs), id: \.self) { tagID in
                    if let tag = AllRecipeTags.shared.getTag(byId: tagID) {
                        TagChip(tag: tag)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 4)
        .accessibilityLabel("Recipe tags")
    }
}

// Flow layout for better tag distribution
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > width {
                // Move to next row
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
        
        height = currentY + rowHeight
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > bounds.width + bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

#Preview {
    let sampleTags = Set(["meal_breakfast", "attr_kid_friendly", "method_quick_easy", "cuisine_italian", "meal_dinner"])
    
    return VStack {
        RecipeTagsView(tagIDs: sampleTags)
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            .padding()
    }
}