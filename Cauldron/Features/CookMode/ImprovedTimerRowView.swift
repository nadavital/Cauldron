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
                    .font(.system(size: timerFontSize, weight: .bold, design: .rounded))
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
                        .frame(width: 50, height: 50)
                        .background(Color.cauldronOrange)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .shadow(color: Color.cauldronOrange.opacity(0.3), radius: 4)
                }
                .accessibilityLabel(timer.isRunning ? "Pause \(timer.spec.label) timer" : "Resume \(timer.spec.label) timer")

                Button {
                    timerManager.stopTimer(id: timer.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .frame(width: 50, height: 50)
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.secondary)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Stop \(timer.spec.label) timer")
            }
        }
        .padding(16)
        .background(didComplete ? Color.cauldronOrange.opacity(0.18) : Color.cauldronSecondaryBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cauldronOrange.opacity(didComplete ? 0.6 : 0), lineWidth: 2)
        )
        .scaleEffect(didComplete ? 1.03 : 1.0)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
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
    let timerManager: TimerManager
    let recipeName: String
    let stepIndex: Int
    
    @State private var showingCustomTimer = false
    @State private var customMinutes: Int = 5
    @State private var customLabel: String = ""
    
    var body: some View {
        Menu {
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
            Label("Add Timer", systemImage: "timer.circle")
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.cauldronOrange.opacity(0.15))
                .foregroundColor(.cauldronOrange)
                .cornerRadius(8)
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
        }
    }
    
    private func startTimer(minutes: Int, label: String) {
        let spec = TimerSpec(
            id: UUID(),
            seconds: minutes * 60,
            label: label
        )
        timerManager.startTimer(spec: spec, stepIndex: stepIndex, recipeName: recipeName)
    }
}
