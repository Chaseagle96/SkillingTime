import AppIntents
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Widgets read the snapshot the app writes to the App Group. A second entry at
/// the next midnight resets "today" even if the app has not been opened.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let stored = WidgetSnapshotStore.load()
        completion(SnapshotEntry(date: .now, snapshot: stored ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshotStore.load()
        var entries = [SnapshotEntry(date: now, snapshot: snapshot)]
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(SnapshotEntry(date: midnight, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Today widget

struct SkillingTimeTodayWidget: Widget {
    static let kind = "SkillingTimeToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.09, blue: 0.08), Color(red: 0.05, green: 0.05, blue: 0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Today")
        .description("Today's practice and the Skill closest to its next level.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var todaySeconds: Int { entry.snapshot?.todaySeconds(at: entry.date) ?? 0 }
    private var todayXP: Int { entry.snapshot?.todayXP(at: entry.date) ?? 0 }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(WidgetDuration.compact(todaySeconds)) skilled today", systemImage: "hourglass")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(WidgetDuration.compact(todaySeconds)) today")
                    .font(.headline)
                    .widgetAccentable()
                if let skill = entry.snapshot?.closestToLevel, let seconds = skill.secondsToNextLevel {
                    Text("\(skill.name): \(WidgetDuration.compact(seconds)) to Lv \(skill.level + 1)")
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text("Time is XP")
                        .font(.caption)
                }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                todaySummary
                weekBars
            }
        default:
            todaySummary
        }
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Today", systemImage: "sun.max.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.gold)
            Text(WidgetDuration.compact(todaySeconds))
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text("\(todayXP.formatted()) XP")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            if let skill = entry.snapshot?.closestToLevel, let seconds = skill.secondsToNextLevel {
                HStack(spacing: 6) {
                    Image(systemName: skill.symbolName)
                        .foregroundStyle(Color(widgetHex: skill.accentHex))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(skill.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(WidgetDuration.compact(seconds)) to Lv \(skill.level + 1)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
            } else if entry.snapshot == nil {
                Text("Open Skilling Time to begin.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekBars: some View {
        let values = entry.snapshot?.weekDaySeconds ?? Array(repeating: 0, count: 7)
        let peak = max(values.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, seconds in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == values.count - 1 ? WidgetPalette.gold : Color.white.opacity(0.35))
                        .frame(height: max(4, 70 * CGFloat(seconds) / CGFloat(peak)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Practice over the last seven days")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Quick start widget

struct SkillingTimeQuickStartWidget: Widget {
    static let kind = "SkillingTimeQuickStart"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            QuickStartWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.07, green: 0.07, blue: 0.08)
                }
        }
        .configurationDisplayName("Quick Start")
        .description("Start timing one of your recent Skills with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

private struct QuickStartWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var skills: [WidgetSkillSummary] { entry.snapshot?.recentSkills ?? [] }

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let skill = skills.first {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: skill.symbolName)
                        .font(.title3)
                        .widgetAccentable()
                }
                .widgetURL(URL(string: "skillingtime://start/\(skill.id.uuidString)"))
                .accessibilityLabel("Start \(skill.name)")
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "play.fill")
                }
            }
        default:
            let limit = family == .systemMedium ? 4 : 2
            VStack(alignment: .leading, spacing: 8) {
                Label("Start", systemImage: "play.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.gold)
                if skills.isEmpty {
                    Text("Open Skilling Time to add your Skills.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    let columns = family == .systemMedium
                        ? [GridItem(.flexible()), GridItem(.flexible())]
                        : [GridItem(.flexible())]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(skills.prefix(limit)) { skill in
                            Button(intent: StartSkillSessionIntent(skill: SkillEntity(summary: skill))) {
                                HStack(spacing: 6) {
                                    Image(systemName: skill.symbolName)
                                        .foregroundStyle(Color(widgetHex: skill.accentHex))
                                        .frame(width: 18)
                                    Text(skill.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.white)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start \(skill.name)")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Helpers

enum WidgetPalette {
    static let gold = Color(red: 0.82, green: 0.66, blue: 0.29)
}

enum WidgetDuration {
    static func compact(_ seconds: Int) -> String {
        DurationText.compact(seconds)
    }
}

extension WidgetSnapshot {
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: .now,
            skills: [
                WidgetSkillSummary(
                    id: UUID(),
                    name: "Cooking",
                    symbolName: "frying.pan.fill",
                    accentHex: "D97A43",
                    level: 12,
                    fractionToNextLevel: 0.8,
                    secondsToNextLevel: 420,
                    latestSessionAt: .now
                )
            ],
            dayStart: Calendar.current.startOfDay(for: .now),
            todaySeconds: 2_700,
            todayXP: 900,
            weekDaySeconds: [1_200, 0, 2_400, 1_800, 600, 3_000, 2_700]
        )
    }
}

private extension Color {
    init(widgetHex: String) {
        let cleaned = widgetHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        guard cleaned.count == 6 else {
            self = WidgetPalette.gold
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
