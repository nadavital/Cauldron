import SwiftUI

struct InstructionsSection: View {
    @Binding var instructions: [StringInput]
    @Binding var isEditMode: Bool
    @Binding var draggedInstruction: StringInput?
    let cleanupEmptyRows: () -> Void
    let scheduleCleanup: () -> Void
    let checkAndAddPlaceholder: () -> Void
    let startDrag: (StringInput) -> Void
    
    // State for drag reordering
    @State private var draggingItem: StringInput?
    @State private var dragOffset: CGSize = .zero
    @State private var draggedItemHeight: CGFloat = 0
    @State private var lastPlaceholderIndex: Int = 0
    @State private var isDragging = false
    @State private var currentDragIndex: Int? = nil
    @State private var draggingFromIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Instructions", systemImage: "list.number")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    withAnimation {
                        isEditMode.toggle()
                        cleanupEmptyRows()
                        // Reset drag state when toggling edit mode
                        draggingItem = nil
                        dragOffset = .zero
                        isDragging = false
                        currentDragIndex = nil
                        draggingFromIndex = nil
                    }
                }) {
                    Text(isEditMode ? "Done" : "Edit")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
                        .foregroundColor(.accentColor)
                }
                if !isEditMode {
                    Button(action: {
                        withAnimation {
                            if let idx = instructions.firstIndex(where: { $0.isPlaceholder }) {
                                instructions.insert(StringInput(value: "", isPlaceholder: false), at: idx)
                                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { 
                                    if idx < instructions.count {
                                        instructions[idx].isFocused = true 
                                    }
                                }
                            } else {
                                instructions.append(StringInput(value: "", isPlaceholder: false))
                                let newIdx = instructions.count-1
                                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { 
                                    if newIdx < instructions.count {
                                        instructions[newIdx].isFocused = true 
                                    }
                                }
                            }
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            // Items container
            ZStack(alignment: .top) {
                VStack(spacing: isEditMode ? 5 : 10) {
                    ForEach(instructions.indices, id: \.self) { index in
                        if isEditMode {
                            let item = instructions[index]
                            let isLastPlaceholder = index == instructions.count - 1 && (item.value.isEmpty || item.isPlaceholder)
                            
                            InstructionRowView(
                                item: item, 
                                index: index,
                                stepNumber: index + 1,
                                isLastPlaceholder: isLastPlaceholder, 
                                isDragged: draggingItem?.id == item.id && isDragging
                            )
                            .opacity(draggingItem?.id == item.id && isDragging ? 0 : 1)
                            .offset(y: offsetForItem(at: index))
                            .zIndex(draggingItem?.id == item.id && isDragging ? 1 : 0)
                            .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: currentDragIndex)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            if draggedItemHeight == 0 {
                                                draggedItemHeight = geo.size.height
                                            }
                                            
                                            // Keep track of the last placeholder item
                                            if isLastPlaceholder {
                                                lastPlaceholderIndex = index
                                            }
                                        }
                                }
                            )
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        // Don't allow dragging the last placeholder
                                        if isLastPlaceholder { return }
                                        
                                        // Start dragging if not already dragging
                                        if !isDragging {
                                            withAnimation(.easeInOut(duration: 0.1)) {
                                                isDragging = true
                                                draggingItem = item
                                                currentDragIndex = index
                                                draggingFromIndex = index
                                            }
                                        }
                                        
                                        // Update the position of the dragged item
                                        dragOffset = value.translation
                                        
                                        // Calculate new index based on drag position
                                        if draggedItemHeight > 0 {
                                            let newIndex = calculateNewIndex(from: index, offset: value.translation.height)
                                            
                                            if newIndex != currentDragIndex {
                                                // Provide haptic feedback when changing position
                                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                                impactFeedback.impactOccurred()
                                                
                                                currentDragIndex = newIndex
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        // If we were dragging, update the array order
                                        if isDragging, let fromIndex = draggingFromIndex, let toIndex = currentDragIndex, fromIndex != toIndex {
                                            let movedItem = instructions.remove(at: fromIndex)
                                            instructions.insert(movedItem, at: toIndex)
                                        }
                                        
                                        // Reset dragging state
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            isDragging = false
                                            dragOffset = .zero
                                            draggingItem = nil
                                            currentDragIndex = nil
                                            draggingFromIndex = nil
                                        }
                                    }
                            )
                        } else {
                            InstructionInputRow(
                                instruction: $instructions[index].value,
                                stepNumber: index + 1,
                                isFocused: $instructions[index].isFocused
                            )
                            .onChange(of: instructions[index].isFocused) {
                                if instructions[index].isFocused { checkAndAddPlaceholder() }
                            }
                            .onChange(of: instructions[index].value) {
                                if index == instructions.count - 1 && !instructions[index].value.isEmpty {
                                    withAnimation { 
                                        instructions.append(StringInput(value: "", isPlaceholder: false)) 
                                    }
                                } else if instructions[index].value.isEmpty && index != instructions.count - 1 {
                                    scheduleCleanup()
                                }
                            }
                        }
                    }
                }
                
                // Floating dragged item
                if let item = draggingItem, isDragging, let currentIndex = currentDragIndex {
                    InstructionRowView(
                        item: item, 
                        index: currentIndex,
                        stepNumber: currentIndex + 1,
                        isLastPlaceholder: false, 
                        isDragged: true
                    )
                    .offset(y: calculateDraggedItemOffset(currentIndex: currentIndex))
                    .zIndex(100)
                    .transition(.identity)
                }
            }
            .onChange(of: instructions) { newInstructions in
                // Update the last placeholder index when instructions change
                if let lastIdx = newInstructions.indices.last,
                   newInstructions[lastIdx].value.isEmpty || newInstructions[lastIdx].isPlaceholder {
                    lastPlaceholderIndex = lastIdx
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    // Calculate offset for each item based on drag state
    private func offsetForItem(at index: Int) -> CGFloat {
        // Don't move anything if not dragging
        if !isDragging {
            return 0
        }
        
        // Don't move the item being dragged (it's hidden anyway)
        if let draggingItem = draggingItem, instructions[index].id == draggingItem.id {
            return 0
        }
        
        // If we're dragging and have valid indices
        if let currentDragIndex = currentDragIndex, let fromIndex = draggingFromIndex {
            // If item is between from and to indices (or to and from), move it
            if fromIndex < currentDragIndex { // Dragging down
                if index > fromIndex && index <= currentDragIndex {
                    return -draggedItemHeight
                }
            } else if fromIndex > currentDragIndex { // Dragging up
                if index >= currentDragIndex && index < fromIndex {
                    return draggedItemHeight
                }
            }
        }
        
        return 0
    }
    
    // Calculate the position of the dragged item
    private func calculateDraggedItemOffset(currentIndex: Int) -> CGFloat {
        guard let fromIndex = draggingFromIndex else { return 0 }
        
        // Base position is where the item started
        let baseOffset = CGFloat(fromIndex) * draggedItemHeight
        
        // Add the user's drag offset
        return baseOffset + dragOffset.height
    }
    
    // Calculate the new index based on drag position
    private func calculateNewIndex(from startIndex: Int, offset: CGFloat) -> Int {
        let estimatedIndex = startIndex + Int(round(offset / draggedItemHeight))
        
        // Don't allow moving to or beyond the last placeholder
        let maxAllowedIndex = max(0, min(lastPlaceholderIndex - 1, instructions.count - 2))
        
        // Bound the index within valid range
        return max(0, min(estimatedIndex, maxAllowedIndex))
    }
}

// Extracted view for instruction row
struct InstructionRowView: View {
    let item: StringInput
    let index: Int
    let stepNumber: Int
    let isLastPlaceholder: Bool
    let isDragged: Bool
    
    var body: some View {
        HStack(alignment: .top) {
            // Drag handle in a VStack to center it vertically
            VStack {
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18))
                    .foregroundColor(isLastPlaceholder ? .gray.opacity(0.3) : .gray)
                    .frame(width: 36, height: 36)
                    .background(Color.gray.opacity(isLastPlaceholder ? 0.05 : 0.1))
                    .cornerRadius(8)
                Spacer()
            }
            
            InstructionInputRow(
                instruction: .constant(item.value),
                stepNumber: stepNumber,
                isFocused: .constant(item.isFocused)
            )
            
            // Wrap the delete button in a VStack to center it vertically
            VStack {
                Spacer()
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                    .padding(.leading, 2)
                    .opacity(isLastPlaceholder ? 0.3 : 1)
                Spacer()
            }
        }
        .padding(6)
        .background(isLastPlaceholder ? Color.white.opacity(0.3) : Color.white.opacity(0.5))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(isDragged ? 0.3 : 0.1), 
                radius: isDragged ? 5 : 1)
        .scaleEffect(isDragged ? 1.05 : 1.0)
    }
}
