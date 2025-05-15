import SwiftUI

struct InstructionsSection: View {
    @Binding var instructions: [StringInput]
    @Binding var isEditMode: Bool
    @Binding var draggedInstruction: StringInput?
    let cleanupEmptyRows: () -> Void
    let scheduleCleanup: () -> Void
    let checkAndAddPlaceholder: () -> Void
    let startDrag: (StringInput) -> Void

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
                                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { instructions[idx].isFocused = true }
                            } else {
                                instructions.append(StringInput(value: "", isPlaceholder: false))
                                let newIdx = instructions.count-1
                                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { instructions[newIdx].isFocused = true }
                            }
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            VStack(spacing: 10) {
                ForEach($instructions) { $instruction in
                    if isEditMode {
                        HStack(alignment: .top) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.trailing, 2)
                                .onDrag { startDrag(instruction); return NSItemProvider() }
                                .onDrop(of: [.text], delegate: InstructionDropDelegate(item: instruction, instructions: $instructions, draggedItem: $draggedInstruction))
                            InstructionInputRow(
                                instruction: $instruction.value,
                                stepNumber: (instructions.firstIndex(where: { $0.id == instruction.id }) ?? -1) + 1,
                                isFocused: $instruction.isFocused
                            )
                            Button(action: {
                                withAnimation { instructions.removeAll { $0.id == instruction.id }; cleanupEmptyRows() }
                            }) {
                                Image(systemName: "minus.circle.fill").font(.title3).foregroundColor(.red)
                            }.padding(.leading, 8)
                        }
                    } else {
                        InstructionInputRow(
                            instruction: $instruction.value,
                            stepNumber: (instructions.firstIndex(where: { $0.id == instruction.id }) ?? -1) + 1,
                            isFocused: $instruction.isFocused
                        )
                        .onChange(of: instruction.isFocused) { focused in
                            if focused { checkAndAddPlaceholder() }
                        }
                        .onChange(of: instruction.value) { new in
                            if instruction.id == instructions.last?.id && !new.isEmpty {
                                withAnimation { instructions.append(StringInput(value: "", isPlaceholder: false)) }
                            } else if new.isEmpty && instruction.id != instructions.last?.id {
                                scheduleCleanup()
                            }
                        }
                    }
                }
                .transition(.asymmetric(insertion: .scale, removal: .opacity))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    struct InstructionDropDelegate: DropDelegate {
        let item: StringInput
        @Binding var instructions: [StringInput]
        @Binding var draggedItem: StringInput?
        func performDrop(info: DropInfo) -> Bool { draggedItem = nil; return true }
        func dropEntered(info: DropInfo) {
            guard let dragged = draggedItem,
                  let from = instructions.firstIndex(where: { $0.id == dragged.id }),
                  let to = instructions.firstIndex(where: { $0.id == item.id }),
                  from != to,
                  !instructions[from].isPlaceholder,
                  !instructions[to].isPlaceholder else { return }
            withAnimation { instructions.move(fromIndex: from, toIndex: to) }
        }
        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    }
}
