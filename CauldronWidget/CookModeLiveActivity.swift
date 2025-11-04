//
//  CookModeLiveActivity.swift
//  CauldronWidget
//
//  Live Activity views for Cook Mode - Lock Screen and Dynamic Island
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// Live Activity widget for Cook Mode
struct CookModeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookModeActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                // Expanded Region
                DynamicIslandExpandedRegion(.leading) {
                    // Recipe emoji/icon and name
                    HStack(alignment: .center, spacing: 8) {
                        if let emoji = context.attributes.recipeEmoji {
                            Text(emoji)
                                .font(.largeTitle)
                        } else {
                            Image("CauldronIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.recipeName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    // Step progress
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Step")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(context.state.currentStep + 1)/\(context.state.totalSteps)")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }

                DynamicIslandExpandedRegion(.center) {
                    // Progress bar and instruction
                    VStack(spacing: 8) {
                        ProgressView(value: context.state.progressPercentage)
                            .tint(.orange)
                            .frame(height: 6)

                        // Current step instruction
                        Text(context.state.stepInstruction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        // Timer info below instruction
                        if let durationSeconds = context.state.primaryTimerDurationSeconds {
                            let minutes = durationSeconds / 60
                            let seconds = durationSeconds % 60
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.caption)
                                    .foregroundStyle(.orange)

                                Circle()
                                    .fill(context.state.primaryTimerIsRunning ? Color.green : Color.orange)
                                    .frame(width: 4, height: 4)

                                Text(String(format: "%d:%02d", minutes, seconds))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .monospacedDigit()

                                Text(context.state.primaryTimerIsRunning ? "Running" : "Paused")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // Step navigation buttons
                    HStack(spacing: 16) {
                        // Previous button
                        Button(intent: PreviousStepIntent()) {
                            Label("Previous", systemImage: "chevron.left")
                                .font(.caption2)
                        }
                        .disabled(context.state.currentStep == 0)
                        .foregroundStyle(context.state.currentStep > 0 ? .primary : .tertiary)

                        Spacer()

                        // Next button
                        Button(intent: NextStepIntent()) {
                            Label("Next", systemImage: "chevron.right")
                                .font(.caption2)
                                .labelStyle(.trailingIcon)
                        }
                        .disabled(context.state.currentStep >= context.state.totalSteps - 1)
                        .foregroundStyle(context.state.currentStep < context.state.totalSteps - 1 ? .primary : .tertiary)
                    }
                    .padding(.horizontal)
                }
            } compactLeading: {
                // Compact Leading (left side of notch)
                if let emoji = context.attributes.recipeEmoji {
                    Text(emoji)
                        .font(.body)
                } else {
                    Image("CauldronIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } compactTrailing: {
                // Compact Trailing (right side of notch)
                // Show timer when active, step count otherwise
                if let durationSeconds = context.state.primaryTimerDurationSeconds {
                    let minutes = durationSeconds / 60
                    let seconds = durationSeconds % 60
                    HStack(spacing: 2) {
                        // Status indicator
                        if context.state.primaryTimerIsRunning {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                        }
                        Text(String(format: "%d:%02d", minutes, seconds))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .frame(minWidth: 35, alignment: .trailing)
                } else {
                    // No timer - show step progress
                    Text("\(context.state.currentStep + 1)/\(context.state.totalSteps)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .frame(minWidth: 35, alignment: .trailing)
                }
            } minimal: {
                // Minimal (single icon when collapsed) - use Cauldron icon
                if let emoji = context.attributes.recipeEmoji {
                    Text(emoji)
                        .font(.system(size: 20))
                } else {
                    Image("CauldronIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
            }
        }
    }
}

// MARK: - Lock Screen View

/// Lock screen Live Activity view
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<CookModeActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            // Header: Recipe name and progress
            HStack(spacing: 8) {
                if let emoji = context.attributes.recipeEmoji {
                    Text(emoji)
                        .font(.title2)
                } else {
                    Image("CauldronIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.recipeName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text("Step \(context.state.currentStep + 1) of \(context.state.totalSteps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Timer badge
                if context.state.activeTimerCount > 0 {
                    TimerBadgeView(
                        count: context.state.activeTimerCount,
                        durationSeconds: context.state.primaryTimerDurationSeconds,
                        isRunning: context.state.primaryTimerIsRunning
                    )
                }
            }

            // Progress bar
            ProgressView(value: context.state.progressPercentage)
                .tint(.orange)
                .frame(height: 6)

            // Current step instruction
            if !context.state.stepInstruction.isEmpty {
                Text(context.state.stepInstruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Navigation buttons
            HStack(spacing: 12) {
                // Previous button
                Button(intent: PreviousStepIntent()) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Previous")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }
                .disabled(context.state.currentStep == 0)
                .tint(.orange)

                // Next button
                Button(intent: NextStepIntent()) {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }
                .disabled(context.state.currentStep >= context.state.totalSteps - 1)
                .tint(.orange)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .activityBackgroundTint(Color(white: 0.1))
        .activitySystemActionForegroundColor(.orange)
    }
}

// MARK: - Helper Views

/// Timer badge showing active timer count and status
struct TimerBadgeView: View {
    let count: Int
    let durationSeconds: Int?
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 4) {
            // Status-colored timer icon
            Image(systemName: "timer")
                .font(.caption2)
                .foregroundStyle(isRunning ? .green : .orange)

            if let duration = durationSeconds {
                let minutes = duration / 60
                let seconds = duration % 60
                Text(String(format: "%d:%02d", minutes, seconds))
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            } else {
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isRunning ? Color.green.opacity(0.15) : Color.orange.opacity(0.2))
        .foregroundStyle(isRunning ? .green : .orange)
        .clipShape(Capsule())
    }
}

/// Custom label style for trailing icon
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle {
        TrailingIconLabelStyle()
    }
}
