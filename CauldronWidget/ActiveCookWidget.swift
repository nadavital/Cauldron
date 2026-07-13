import SwiftUI
import WidgetKit
import AppIntents

private struct ActiveCookEntry: TimelineEntry {
    let date: Date
    let snapshot: CookSessionSharedSnapshot?
}

private struct ActiveCookProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveCookEntry {
        ActiveCookEntry(
            date: .now,
            snapshot: CookSessionSharedSnapshot(
                recipeID: UUID(),
                stepIndex: 1,
                totalSteps: 5,
                sessionStartTime: .now,
                stepInstructions: ["Prep ingredients", "Simmer until tender", "Season and serve"]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveCookEntry) -> Void) {
        completion(ActiveCookEntry(date: .now, snapshot: CookSessionSharedStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveCookEntry>) -> Void) {
        let entry = ActiveCookEntry(date: .now, snapshot: CookSessionSharedStore.read())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct ActiveCookWidget: Widget {
    let kind = "ActiveCookWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveCookProvider()) { entry in
            ActiveCookWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "cauldron://cook/resume"))
        }
        .configurationDisplayName("Cook Mode")
        .description("See and control the current recipe step without opening Cauldron.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct ActiveCookWidgetView: View {
    let entry: ActiveCookEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 10) {
                Label("Cook Mode", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Step \(snapshot.stepIndex + 1) of \(snapshot.totalSteps)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let instructions = snapshot.stepInstructions,
                   instructions.indices.contains(snapshot.stepIndex) {
                    Text(instructions[snapshot.stepIndex])
                        .font(family == .systemSmall ? .callout : .title3)
                        .fontWeight(.semibold)
                        .lineLimit(family == .systemLarge ? 6 : 3)
                }
                Spacer(minLength: 0)
                HStack {
                    Button(intent: PreviousStepIntent()) {
                        Label("Previous", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(snapshot.stepIndex == 0)
                    Spacer()
                    ProgressView(
                        value: Double(snapshot.stepIndex + 1),
                        total: Double(snapshot.totalSteps)
                    )
                    .frame(maxWidth: family == .systemSmall ? 50 : 150)
                    Spacer()
                    Button(intent: NextStepIntent()) {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(snapshot.stepIndex >= snapshot.totalSteps - 1)
                }
                .buttonStyle(.borderless)
            }
        } else {
            ContentUnavailableView {
                Label("Ready to Cook", systemImage: "fork.knife")
            } description: {
                Text("Start Cook Mode from any recipe.")
            }
        }
    }
}
