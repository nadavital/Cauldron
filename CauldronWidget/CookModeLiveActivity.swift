//
//  CookModeLiveActivity.swift
//  CauldronWidget
//
//  Live Activity views for Cook Mode - Lock Screen and Dynamic Island
//

import ActivityKit
import WidgetKit
import SwiftUI

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
                    HStack(spacing: 8) {
                        if let emoji = context.attributes.recipeEmoji {
                            Text(emoji)
                                .font(.title2)
                        } else {
                            Image("CauldronIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.recipeName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Text("Step \(context.state.currentStep + 1) of \(context.state.totalSteps)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    // Timer display
                    if let timerSeconds = context.state.primaryTimerSeconds {
                        VStack(alignment: .trailing, spacing: 2) {
                            Image(systemName: "timer")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            Text(formatTime(timerSeconds))
                                .font(.caption)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                    } else if context.state.activeTimerCount > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Image(systemName: "timer")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            Text("\(context.state.activeTimerCount) active")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    // Progress bar
                    VStack(spacing: 8) {
                        ProgressView(value: context.state.progressPercentage)
                            .tint(.orange)
                            .frame(height: 6)

                        // Current step instruction (truncated)
                        Text(context.state.stepInstruction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // Step navigation hint
                    HStack(spacing: 16) {
                        Label("Previous", systemImage: "chevron.left")
                            .font(.caption2)
                            .foregroundStyle(context.state.currentStep > 0 ? .primary : .tertiary)

                        Spacer()

                        Label("Next", systemImage: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(context.state.currentStep < context.state.totalSteps - 1 ? .primary : .tertiary)
                            .labelStyle(.trailingIcon)
                    }
                    .padding(.horizontal)
                }
            } compactLeading: {
                // Compact Leading (left side of notch)
                if let emoji = context.attributes.recipeEmoji {
                    Text(emoji)
                        .font(.caption)
                } else {
                    Image("CauldronIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } compactTrailing: {
                // Compact Trailing (right side of notch)
                HStack(spacing: 4) {
                    // Step progress
                    Text("\(context.state.currentStep + 1)/\(context.state.totalSteps)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()

                    // Timer indicator
                    if let timerSeconds = context.state.primaryTimerSeconds {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(formatTime(timerSeconds))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            } minimal: {
                // Minimal (single icon when collapsed)
                if let timerSeconds = context.state.primaryTimerSeconds {
                    // Show timer countdown when timer is active
                    VStack(spacing: 0) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text(formatTimeMinimal(timerSeconds))
                            .font(.system(size: 8))
                            .monospacedDigit()
                    }
                } else {
                    // Show Cauldron icon
                    Image("CauldronIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
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
                        .font(.title3)
                } else {
                    Image("CauldronIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
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
                        primarySeconds: context.state.primaryTimerSeconds
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
        }
        .padding(16)
        .activityBackgroundTint(Color(white: 0.1))
        .activitySystemActionForegroundColor(.orange)
    }
}

// MARK: - Helper Views

/// Timer badge showing active timer count and countdown
struct TimerBadgeView: View {
    let count: Int
    let primarySeconds: Int?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption2)

            if let seconds = primarySeconds {
                Text(formatTime(seconds))
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            } else {
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.orange.opacity(0.2))
        .foregroundStyle(.orange)
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

// MARK: - Helper Functions

/// Format seconds into MM:SS format
func formatTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return String(format: "%d:%02d", minutes, remainingSeconds)
}

/// Format seconds into minimal format (M:SS or SS)
func formatTimeMinimal(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60

    if minutes > 0 {
        return String(format: "%d:%02d", minutes, remainingSeconds)
    } else {
        return String(format: "%02d", remainingSeconds)
    }
}
