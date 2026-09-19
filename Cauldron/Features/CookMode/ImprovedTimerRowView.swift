//
//  ImprovedTimerRowView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import SwiftUI

/// Improved timer row with better UI and state management
struct ImprovedTimerRowView: View {
    let timer: ActiveTimer
    let timerManager: TimerManager
    var isWorkbench = false

    @State private var remainingSeconds: Int = 0
    @State private var updateTask: Task<Void, Never>?
    @State private var didComplete = false
    /// Scales the large timer readout with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize: CGFloat = 32
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(timer.spec.label)
                    .font(.headline)

                Text(formatTime(remainingSeconds))
                    .font(.system(size: isWorkbench ? timerFontSize * 0.85 : timerFontSize, weight: isWorkbench ? .semibold : .bold, design: .rounded))
                    .foregroundColor(remainingSeconds <= 10 && timer.isRunning ? .red : .cauldronOrange)
                    .monospacedDigit()

                if !timer.isRunning, let pausedAt = timer.pausedAt {
                    Text("Paused at \(pausedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(timer.spec.label)
            .accessibilityValue(spokenRemaining)
            .accessibilityAddTraits(.updatesFrequently)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    if timer.isRunning {
                        timerManager.pauseTimer(id: timer.id)
                    } else {
                        timerManager.resumeTimer(id: timer.id)
                    }
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: isWorkbench ? 44 : 50, height: isWorkbench ? 44 : 50)
                        .background(isWorkbench ? Color.cauldronOrange.opacity(0.12) : Color.cauldronOrange)
                        .foregroundColor(isWorkbench ? .cauldronOrange : .white)
                        .clipShape(Circle())
                        .shadow(color: Color.cauldronOrange.opacity(isWorkbench ? 0 : 0.3), radius: 4)
                }
                .accessibilityLabel(timer.isRunning ? "Pause \(timer.spec.label) timer" : "Resume \(timer.spec.label) timer")

                Button {
                    timerManager.stopTimer(id: timer.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .frame(width: isWorkbench ? 44 : 50, height: isWorkbench ? 44 : 50)
                        .background(Color.secondary.opacity(isWorkbench ? 0.08 : 0.2))
                        .foregroundColor(.secondary)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Stop \(timer.spec.label) timer")
            }
        }
        .padding(isWorkbench ? 0 : 16)
        .background(didComplete ? Color.cauldronOrange.opacity(0.18) : (isWorkbench ? Color.clear : Color.cauldronSecondaryBackground))
        .cornerRadius(Theme.Radius.large)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large)
                .stroke(Color.cauldronOrange.opacity(didComplete ? 0.6 : 0), lineWidth: 2)
        )
        .scaleEffect(didComplete ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isWorkbench ? 0 : 0.05), radius: 8, x: 0, y: 4)
        .animation(Theme.Animation.spring, value: didComplete)
        .onChange(of: remainingSeconds) { _, newValue in
            // Celebrate the moment a running timer hits zero.
            if newValue <= 0 && !didComplete {
                didComplete = true
                Haptics.success()
            } else if newValue > 0 && didComplete {
                didComplete = false
            }
        }
        .onAppear {
            startUpdating()
        }
        .onDisappear {
            updateTask?.cancel()
        }
    }
    
    private func startUpdating() {
        remainingSeconds = timerManager.getRemainingTime(id: timer.id)
        
        updateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Update every 1.0s
                if !Task.isCancelled {
                    remainingSeconds = timerManager.getRemainingTime(id: timer.id)
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }

    /// Natural-language remaining time for VoiceOver, e.g. "2 minutes 30 seconds remaining, running".
    private var spokenRemaining: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = remainingSeconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        let duration = formatter.string(from: TimeInterval(max(0, remainingSeconds))) ?? "\(remainingSeconds) seconds"
        let state = timer.isRunning ? "running" : "paused"
        return "\(duration) remaining, \(state)"
    }
}

/// Quick timer creation view
struct QuickTimerButton: View {
    @ObservedObject var timerManager: TimerManager
    let recipeName: String
    let stepIndex: Int
    var showsInlineControls = false
    var isWorkbenchControl = false
    var suggestedTimers: [TimerSpec] = []
    
    @State private var showingCustomTimer = false
    @State private var customMinutes: Int = 5
    @State private var customLabel: String = ""
    
    var body: some View {
        Group {
            if showsInlineControls {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                    ForEach([5, 10, 15, 30], id: \.self) { minutes in
                        Button {
                            startTimer(minutes: minutes, label: "\(minutes) min timer")
                        } label: {
                            Text("\(minutes) min")
                                .lineLimit(1)
                        }
                    }
                    Button("Custom") { showingCustomTimer = true }
                        .lineLimit(1)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(.cauldronOrange)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Start a timer")
                .font(.subheadline)
            } else {
                Menu {
                    if isWorkbenchControl && !timerManager.activeTimers.isEmpty {
                        Section("Active Timers") {
                            ForEach(timerManager.activeTimers) { timer in
                                Button(timer.isRunning ? "Pause \(timer.spec.label)" : "Resume \(timer.spec.label)",
                                       systemImage: timer.isRunning ? "pause" : "play") {
                                    if timer.isRunning { timerManager.pauseTimer(id: timer.id) }
                                    else { timerManager.resumeTimer(id: timer.id) }
                                }
                                Button("Stop \(timer.spec.label)", systemImage: "stop", role: .destructive) {
                                    timerManager.stopTimer(id: timer.id)
                                }
                            }
                            if timerManager.activeTimers.count > 1 {
                                Button("Stop All", role: .destructive) { timerManager.stopAllTimers() }
                            }
                        }
                    }

                    if !suggestedTimers.isEmpty {
                        Section("Current Step") {
                            ForEach(suggestedTimers) { spec in
                                Button("\(spec.label) · \(spec.displayDuration)") {
                                    timerManager.startTimer(spec: spec, stepIndex: stepIndex, recipeName: recipeName)
                                    Task { await RecipeIntentDonation.recordTimerStarted(spec) }
                                }
                            }
                        }
                    }

                    Button("5 minutes") {
                        startTimer(minutes: 5, label: "5 min timer")
                    }

                    Button("10 minutes") {
                        startTimer(minutes: 10, label: "10 min timer")
                    }

                    Button("15 minutes") {
                        startTimer(minutes: 15, label: "15 min timer")
                    }

                    Button("30 minutes") {
                        startTimer(minutes: 30, label: "30 min timer")
                    }

                    Divider()

                    Button("Custom...") {
                        showingCustomTimer = true
                    }
                } label: {
                    if isWorkbenchControl {
                        Label("Timers", systemImage: "timer")
                    } else {
                        Label("Add Timer", systemImage: "timer.circle")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.cauldronOrange.opacity(0.15))
                            .foregroundColor(.cauldronOrange)
                            .cornerRadius(Theme.Radius.small)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCustomTimer) {
            NavigationStack {
                Form {
                    Section("Timer Duration") {
                        Stepper("\(customMinutes) minutes", value: $customMinutes, in: 1...180)
                    }
                    
                    Section("Label (Optional)") {
                        TextField("e.g., Simmer, Rest, etc.", text: $customLabel)
                    }
                }
                .navigationTitle("Custom Timer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingCustomTimer = false
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") {
                            let label = customLabel.isEmpty ? "\(customMinutes) min timer" : customLabel
                            startTimer(minutes: customMinutes, label: label)
                            showingCustomTimer = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .appSheetSizing(.compact)
        }
    }
    
    private func startTimer(minutes: Int, label: String) {
        let spec = TimerSpec(
            id: UUID(),
            seconds: minutes * 60,
            label: label
        )
        timerManager.startTimer(spec: spec, stepIndex: stepIndex, recipeName: recipeName)
        Task { await RecipeIntentDonation.recordTimerStarted(spec) }
    }
}
