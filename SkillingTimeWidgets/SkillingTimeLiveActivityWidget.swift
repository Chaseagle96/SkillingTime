import ActivityKit
import AppIntents
import Foundation
import SwiftUI
import WidgetKit

struct SkillingTimeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SkillingTimeActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        context.attributes.skillName,
                        systemImage: context.attributes.symbolName
                    )
                    .font(.headline)
                    .foregroundStyle(Color(skillingTimeHex: context.attributes.accentHex))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    activityTimer(state: context.state)
                        .font(.system(.headline, design: .monospaced, weight: .semibold))
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("Level \(context.state.level) · \(context.state.rankName)")
                        .font(.caption.weight(.semibold))
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(value: clamped(context.state.progressFraction))
                            .tint(Color(skillingTimeHex: context.attributes.accentHex))
                        HStack {
                            Text("+\(context.state.xpEarned.formatted()) XP")
                            Spacer()
                            Text("\(context.state.xpRemaining.formatted()) XP remaining")
                        }
                        .font(.caption2)
                        controls(context: context, compact: true)
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(Color(skillingTimeHex: context.attributes.accentHex))
            } compactTrailing: {
                activityTimer(state: context.state)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .frame(maxWidth: 58)
            } minimal: {
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(Color(skillingTimeHex: context.attributes.accentHex))
            }
            .keylineTint(Color(skillingTimeHex: context.attributes.accentHex))
        }
    }

    private func lockScreenView(
        context: ActivityViewContext<SkillingTimeActivityAttributes>
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: context.attributes.symbolName)
                    .font(.title2)
                    .foregroundStyle(Color(skillingTimeHex: context.attributes.accentHex))
                    .frame(width: 42, height: 42)
                    .background(
                        Color(skillingTimeHex: context.attributes.accentHex).opacity(0.14),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.skillName)
                        .font(.headline)
                    Text(context.state.isAwaitingCommit
                        ? "Session ready to review"
                        : "Level \(context.state.level) · \(context.state.rankName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    activityTimer(state: context.state)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                    Text("+\(context.state.xpEarned.formatted()) XP")
                        .font(.caption)
                        .foregroundStyle(Color(skillingTimeHex: context.attributes.accentHex))
                }
            }

            ProgressView(value: clamped(context.state.progressFraction))
                .tint(Color(skillingTimeHex: context.attributes.accentHex))

            if let title = context.state.focusGoalTitle,
               let label = context.state.focusGoalProgressLabel {
                HStack {
                    Label(title, systemImage: "scope")
                        .lineLimit(1)
                    Spacer()
                    Text(label)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            controls(context: context, compact: false)
        }
        .padding(16)
    }

    @ViewBuilder
    private func controls(
        context: ActivityViewContext<SkillingTimeActivityAttributes>,
        compact: Bool
    ) -> some View {
        HStack(spacing: 12) {
            if !context.state.isAwaitingCommit {
                Button(
                    intent: ToggleSkillingTimeSessionIntent(
                        sessionID: context.attributes.sessionID
                    )
                ) {
                    Label(
                        context.state.isPaused ? "Resume" : "Pause",
                        systemImage: context.state.isPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: compact ? nil : .infinity)
                }
                .buttonStyle(.bordered)
            }

            Link(destination: finishURL(for: context.attributes.sessionID)) {
                Label(
                    context.state.isAwaitingCommit ? "Review" : "Finish",
                    systemImage: context.state.isAwaitingCommit
                        ? "doc.text.magnifyingglass"
                        : "checkmark"
                )
                .frame(maxWidth: compact ? nil : .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(skillingTimeHex: context.attributes.accentHex))
        }
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func activityTimer(
        state: SkillingTimeActivityAttributes.ContentState
    ) -> some View {
        if let timerStart = state.effectiveTimerStart {
            Text(timerInterval: timerStart...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        } else {
            Text(formatDuration(state.accumulatedActiveSeconds))
                .monospacedDigit()
        }
    }

    private func finishURL(for sessionID: UUID) -> URL {
        URL(string: "skillingtime://session/\(sessionID.uuidString)/finish")!
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(
            format: "%02d:%02d:%02d",
            safe / 3_600,
            (safe % 3_600) / 60,
            safe % 60
        )
    }
}

private extension Color {
    init(skillingTimeHex: String) {
        let cleaned = skillingTimeHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        if cleaned.count == 6 {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        } else {
            red = 0.82
            green = 0.66
            blue = 0.29
        }
        self.init(red: red, green: green, blue: blue)
    }
}
