//
//  RecipeStepsSection.swift
//  Cauldron
//
//  Displays the cooking steps for a recipe
//

import SwiftUI

struct RecipeStepsSection: View {
    let steps: [CookStep]
    let highlightedStepIndex: Int?
    let onTimerTap: (TimerSpec, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Instructions", systemImage: "list.number")
                .font(.title2)
                .fontWeight(.bold)

            ForEach(sortedSections, id: \.self) { section in
                VStack(alignment: .leading, spacing: 8) {
                    if section != "Main" {
                        Text(section)
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }

                    ForEach(groupedSteps[section] ?? []) { step in
                        StepRow(
                            step: step,
                            isHighlighted: highlightedStepIndex == step.index,
                            onTimerTap: onTimerTap
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }

    private var groupedSteps: [String: [CookStep]] {
        Dictionary(grouping: steps) { $0.section ?? "Main" }
    }

    private var sortedSections: [String] {
        groupedSteps.keys.sorted { section1, section2 in
            if section1 == "Main" { return true }
            if section2 == "Main" { return false }

            let index1 = steps.firstIndex { $0.section == section1 } ?? 0
            let index2 = steps.firstIndex { $0.section == section2 } ?? 0
            return index1 < index2
        }
    }
}

private struct StepRow: View {
    let step: CookStep
    let isHighlighted: Bool
    let onTimerTap: (TimerSpec, Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step.index + 1)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Color.cauldronOrange)
                .clipShape(Circle())
                .fixedSize()

            VStack(alignment: .leading, spacing: 8) {
                Text(step.text.decodingHTMLEntities)
                    .font(.body)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)

                if let timer = step.timers.first {
                    Button {
                        onTimerTap(timer, step.index)
                    } label: {
                        Label(timer.displayDuration, systemImage: "timer")
                            .font(.caption)
                            .foregroundColor(.cauldronOrange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cauldronOrange.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHighlighted ? Color.cauldronOrange.opacity(0.15) : Color.clear)
        .cornerRadius(12)
        .id("step-\(step.index)")
    }
}

#Preview {
    RecipeStepsSection(
        steps: [
            CookStep(index: 0, text: "Preheat oven to 350°F", timers: []),
            CookStep(index: 1, text: "Mix dry ingredients together", timers: []),
            CookStep(index: 2, text: "Bake for 30 minutes", timers: [.minutes(30)])
        ],
        highlightedStepIndex: 1,
        onTimerTap: { _, _ in }
    )
    .padding()
}
