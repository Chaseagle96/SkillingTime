import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var connectivity: SkillingTimeWatchConnectivity

    var body: some View {
        NavigationStack {
            Group {
                if let state = connectivity.receivedState,
                   let session = state.activeSession {
                    WatchActiveSessionView(state: state, session: session)
                } else {
                    WatchHomeView(state: connectivity.receivedState)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            connectivity.activate()
            if connectivity.receivedState == nil {
                connectivity.send(.refresh())
            }
        }
        .alert(
            "Skilling Time",
            isPresented: Binding(
                get: { connectivity.lastErrorMessage != nil },
                set: { if !$0 { connectivity.clearError() } }
            )
        ) {
            Button("OK") { connectivity.clearError() }
        } message: {
            Text(connectivity.lastErrorMessage ?? "The request could not be completed.")
        }
    }
}

private struct WatchHomeView: View {
    @EnvironmentObject private var connectivity: SkillingTimeWatchConnectivity
    let state: WatchStateSnapshot?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Skilling Time")
                        .font(.headline)
                    Text(connectionDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Skilling Time")
                .accessibilityValue(connectionDescription)
            }

            if let statusMessage = state?.statusMessage, !statusMessage.isEmpty {
                Section {
                    Label(statusMessage, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let completion = state?.lastCompletion {
                Section("Last Session") {
                    CompletionSummary(completion: completion)
                }
            }

            Section {
                NavigationLink {
                    WatchSkillPickerView(skills: state?.skills ?? [])
                } label: {
                    Label("Start Skilling", systemImage: "play.circle.fill")
                        .font(.headline)
                        .foregroundStyle(SkillingTimeWatchTheme.gold)
                }
                .accessibilityHint("Choose a Skill to begin a session")
            }

            if let todaySeconds = state?.todayActiveSeconds {
                Section("Today") {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(WatchDurationFormatter.compact(todaySeconds))
                                .font(.headline.monospacedDigit())
                            Text("Skilling time")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(SkillingTimeWatchTheme.gold)
                    }
                }
            }

            if let state, !state.quests.isEmpty {
                Section("Quests") {
                    ForEach(state.quests) { quest in
                        QuestRow(quest: quest)
                    }
                }
            }

            Section("Skills") {
                if let state, !state.skills.isEmpty {
                    ForEach(state.skills.prefix(6)) { skill in
                        SkillRow(skill: skill)
                    }
                } else {
                    Text("Open Skilling Time on iPhone to sync your Skills.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.carousel)
        .refreshable {
            connectivity.send(.refresh(expectedRevision: state?.revision))
        }
    }

    private var connectionDescription: String {
        switch connectivity.connectionState {
        case .connected: "iPhone connected"
        case .phoneUnavailable: "Changes queue until iPhone reconnects"
        case .activating: "Connecting to iPhone…"
        case .unsupported: "WatchConnectivity unavailable"
        case .inactive: "Open Skilling Time on iPhone to sync"
        }
    }
}

private struct WatchSkillPickerView: View {
    @EnvironmentObject private var connectivity: SkillingTimeWatchConnectivity
    @Environment(\.dismiss) private var dismiss
    let skills: [WatchSkillSnapshot]

    var body: some View {
        List(skills) { skill in
            Button {
                connectivity.send(.start(skillID: skill.id, expectedRevision: connectivity.receivedState?.revision))
                SkillingTimeWatchHaptics.started()
                dismiss()
            } label: {
                SkillRow(skill: skill, showsProgress: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts a Skilling session for \(skill.name)")
        }
        .navigationTitle("Choose Skill")
        .listStyle(.carousel)
    }
}

private struct WatchActiveSessionView: View {
    @EnvironmentObject private var connectivity: SkillingTimeWatchConnectivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: WatchStateSnapshot
    let session: ActiveSessionSnapshot
    @State private var showingCancelConfirmation = false

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 10) {
                    if let skill = state.activeSkill {
                        HStack(spacing: 8) {
                            Image(systemName: skill.symbolName)
                                .font(.title3)
                                .foregroundStyle(SkillingTimeWatchTheme.accent(skill.accentHex))
                            Text(skill.name)
                                .font(.headline)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Active Skill")
                        .accessibilityValue(skill.name)
                    }

                    timerView(at: context.date)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .foregroundStyle(session.isPaused ? .secondary : .primary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .accessibilityLabel("Elapsed Skilling time")
                        .accessibilityValue(WatchDurationFormatter.timer(session.elapsedSeconds(at: context.date)))

                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(session.isAwaitingCommit ? SkillingTimeWatchTheme.gold : .secondary)

                    if let skill = state.activeSkill {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Level \(skill.level)")
                                Spacer()
                                Text(skill.rankName)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            ProgressView(value: skill.progressFraction)
                                .tint(SkillingTimeWatchTheme.accent(skill.accentHex))
                                .accessibilityLabel("Skill progress")
                                .accessibilityValue("\(Int(skill.progressFraction * 100)) percent")
                        }
                    }

                    if let statusMessage = state.statusMessage, !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if session.isAwaitingCommit {
                        ProgressView("Saving session…")
                            .tint(SkillingTimeWatchTheme.gold)
                    } else {
                        controls
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Cancel this session?",
            isPresented: $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Session", role: .destructive) {
                connectivity.send(.session(.cancel, sessionID: session.id, expectedRevision: state.revision))
                SkillingTimeWatchHaptics.paused()
            }
            Button("Keep Session", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var controls: some View {
        if session.isPaused {
            Button {
                connectivity.send(.session(.resume, sessionID: session.id, expectedRevision: state.revision))
                SkillingTimeWatchHaptics.started()
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SkillingTimeWatchTheme.success)
        } else {
            Button {
                connectivity.send(.session(.pause, sessionID: session.id, expectedRevision: state.revision))
                SkillingTimeWatchHaptics.paused()
            } label: {
                Label("Pause", systemImage: "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SkillingTimeWatchTheme.secondaryGold)
        }

        Button {
            connectivity.send(.session(.complete, sessionID: session.id, expectedRevision: state.revision))
            SkillingTimeWatchHaptics.completed()
        } label: {
            Label("Complete", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(SkillingTimeWatchTheme.gold)

        Button("Cancel", role: .destructive) {
            showingCancelConfirmation = true
        }
        .font(.caption)
    }

    private var statusTitle: String {
        if session.isAwaitingCommit { return "Saving on iPhone" }
        if session.isPaused { return "Paused" }
        return "Skilling in progress"
    }

    @ViewBuilder
    private func timerView(at date: Date) -> some View {
        if let activeStart = session.activeSegmentStartedAt {
            let virtualStart = activeStart.addingTimeInterval(
                TimeInterval(-session.accumulatedActiveSeconds)
            )
            Text(timerInterval: virtualStart...Date.distantFuture, countsDown: false)
        } else {
            Text(WatchDurationFormatter.timer(session.elapsedSeconds(at: date)))
        }
    }
}

private struct SkillRow: View {
    let skill: WatchSkillSnapshot
    var showsProgress = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: skill.symbolName)
                .foregroundStyle(SkillingTimeWatchTheme.accent(skill.accentHex))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(skill.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("Level \(skill.level) · \(skill.rankName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if showsProgress {
                Text("\(skill.sessionCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Sessions")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(skill.name)
        .accessibilityValue("Level \(skill.level), \(skill.rankName), \(skill.sessionCount) sessions")
    }
}

private struct QuestRow: View {
    let quest: WatchQuestSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(quest.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 4)
                if quest.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SkillingTimeWatchTheme.success)
                }
            }
            ProgressView(value: quest.fractionComplete)
                .tint(quest.isComplete ? SkillingTimeWatchTheme.success : SkillingTimeWatchTheme.gold)
            Text("\(quest.cadenceTitle) · \(quest.progressLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(quest.title)
        .accessibilityValue("\(quest.progressLabel), \(quest.cadenceTitle)")
    }
}

private struct CompletionSummary: View {
    let completion: WatchCompletionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(completion.skillName)
                .font(.headline)
            Text("\(WatchDurationFormatter.compact(completion.durationSeconds)) · +\(completion.xpEarned) XP")
                .font(.caption)
                .foregroundStyle(SkillingTimeWatchTheme.success)
            Text("Level \(completion.endingLevel) · \(completion.endingRankName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last session complete")
        .accessibilityValue(
            "\(completion.skillName), \(WatchDurationFormatter.compact(completion.durationSeconds)), plus \(completion.xpEarned) XP, level \(completion.endingLevel)"
        )
    }
}
