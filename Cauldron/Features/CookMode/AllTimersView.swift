//
//  AllTimersView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import SwiftUI

/// View showing all active timers across all recipes
struct AllTimersView: View {
    @ObservedObject var timerManager: TimerManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if timerManager.activeTimers.isEmpty {
                    emptyState
                } else {
                    timersList
                }
            }
            .navigationTitle("Active Timers")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if !timerManager.activeTimers.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            timerManager.stopAllTimers()
                        } label: {
                            Text("Stop All")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "timer")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Active Timers")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Timers you start while cooking will appear here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var timersList: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(timerManager.activeTimers) { timer in
                    VStack(alignment: .leading, spacing: 8) {
                        // Recipe and step info
                        HStack {
                            Text(timer.recipeName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("Step \(timer.stepIndex + 1)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.cauldronOrange.opacity(0.2))
                                .cornerRadius(6)
                        }
                        
                        // Timer
                        ImprovedTimerRowView(
                            timer: timer,
                            timerManager: timerManager
                        )
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

#Preview {
    AllTimersView(timerManager: {
        let manager = TimerManager()
        // Add some test timers
        manager.startTimer(
            spec: TimerSpec(id: UUID(), seconds: 300, label: "Simmer"),
            stepIndex: 2,
            recipeName: "Chicken Soup"
        )
        manager.startTimer(
            spec: TimerSpec(id: UUID(), seconds: 1800, label: "Bake"),
            stepIndex: 4,
            recipeName: "Chocolate Cake"
        )
        return manager
    }())
}
