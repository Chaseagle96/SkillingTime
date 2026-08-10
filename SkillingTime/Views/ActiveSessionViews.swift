import SwiftData
import SwiftUI

private struct LevelBanner: Equatable {
    let level: Int
    let isMajor: Bool
}

struct ActiveSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var sessionController: SessionController
    @EnvironmentObject private var liveActivityCoordinator: LiveActivityCoordinator
    @EnvironmentObject private var notificationManager: ProgressionNotificationManager
    @Query(sort: \LifeSkill.sortOrder) private var skills: [LifeSkill]
    @Query private var ledgers: [SkillLedger]

    let skillID: UUID

    @State private var finishDraft: CompletedSessionDraft?
    @State private var showingDiscardAlert = false
    @State private var outcome: SessionOutcome?
    @State private var lastObservedLevel = 0
    @State private var levelBanner: LevelBanner?
    @State private var baseTotalSeconds = 0

    init(skillID: UUID) {
        self.skillID = skillID
        let requestedSkillID = skillID
        _ledgers = Query(
            filter: #Predicate<SkillLedger> { ledger in
                ledger.skillID == requestedSkillID
            }
        )
    }

    private var skill: LifeSkill? { skills.first { $0.id == skillID } }

    var body: some View {
        NavigationStack {
            Group {
                if let outcome {
                    SessionSummaryView(outcome: outcome) {
                        dismiss()
                    }
                } else if let skill,
                          let snapshot = sessionController.activeSession,
                          snapshot.skillID == skillID {
                    activeTimer(skill: skill, snapshot: snapshot)
                } else {
                    EmptyStateCard(
                        systemImage: "timer",
                        title: "Session unavailable",
                        message: "This active session is no longer available."
                    )
                    .padding()
                }
            }
            .toolbar {
                if outcome == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .skillingTimeScreenBackground()
        }
        .sheet(item: $finishDraft) { draft in
            if let skill {
                FinishSessionSheet(
                    skillName: skill.name,
                    curveVersion: skill.progressionCurveVersion,
                    initialSeconds: draft.activeSeconds,
                    onCancel: {
                        sessionController.cancelFinish(
                            shouldResume: draft.shouldResumeOnCancel
                        )
                        finishDraft = nil
                    },
                    onSave: { countedSeconds, note in
                        commitSession(
                            draft: draft,
                            countedSeconds: countedSeconds,
                            note: note,
                            skill: skill
                        )
                    }
                )
            }
        }
        .alert("Discard this session?", isPresented: $showingDiscardAlert) {
            Button("Keep Session", role: .cancel) {}
            Button("Discard", role: .destructive) {
                sessionController.discard()
                dismiss()
            }
        } message: {
            Text("Its elapsed time will not be added to your Skillbook.")
        }
        .onAppear {
            baseTotalSeconds = max(0, ledgers.first?.totalActiveSeconds ?? 0)
            guard let skill, let snapshot = sessionController.activeSession else { return }
            let seconds = baseTotalSeconds + snapshot.elapsedSeconds()
            lastObservedLevel = ProgressionEngine.level(
                forTotalXP: ProgressionEngine.xp(
                    forActiveSeconds: seconds,
                    curveVersion: skill.progressionCurveVersion
                ),
                curveVersion: skill.progressionCurveVersion
            )
            if snapshot.isAwaitingCommit {
                finishDraft = sessionController.requestFinish()
            }
        }
    }

    private func activeTimer(skill: LifeSkill, snapshot: ActiveSessionSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let sessionSeconds = snapshot.elapsedSeconds(at: context.date)
            let startingXP = ProgressionEngine.xp(
                forActiveSeconds: baseTotalSeconds,
                curveVersion: skill.progressionCurveVersion
            )
            let liveXP = ProgressionEngine.xp(
                forActiveSeconds: baseTotalSeconds + sessionSeconds,
                curveVersion: skill.progressionCurveVersion
            )
            let earnedXP = max(0, liveXP - startingXP)
            let progress = ProgressionEngine.progress(
                forTotalXP: liveXP,
                curveVersion: skill.progressionCurveVersion
            )

            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 26)

                    SkillGlyph(
                        symbolName: skill.symbolName,
                        color: Color(hex: skill.accentHex),
                        size: 96,
                        rank: progress.rank
                    )

                    VStack(spacing: 7) {
                        Text(skill.name.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.8)
                            .foregroundStyle(Color(hex: skill.accentHex))

                        Text(DurationText.timer(sessionSeconds))
                            .font(.system(size: 52, weight: .light, design: .monospaced))
                            .minimumScaleFactor(0.65)
                            .contentTransition(.numericText())
                            .accessibilityLabel("Elapsed time")
                            .accessibilityValue(DurationText.compact(sessionSeconds))

                        Text("+\(earnedXP.formatted()) XP")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(SkillingTimeTheme.gold)
                            .contentTransition(.numericText())
                    }

                    progressionCard(skill: skill, progress: progress)

                    if let goal = snapshot.focusGoal {
                        focusGoalCard(
                            FocusGoalProgress.evaluate(
                                goal: goal,
                                sessionSeconds: sessionSeconds,
                                liveTotalXP: liveXP
                            ),
                            accent: Color(hex: skill.accentHex)
                        )
                    }

                    HStack(spacing: 14) {
                        Button {
                            if snapshot.isPaused {
                                sessionController.resume()
                            } else {
                                sessionController.pause()
                            }
                            Haptics.selection()
                        } label: {
                            Label(
                                snapshot.isPaused ? "Resume" : "Pause",
                                systemImage: snapshot.isPaused ? "play.fill" : "pause.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .disabled(snapshot.isAwaitingCommit)

                        Button {
                            finishDraft = sessionController.requestFinish()
                        } label: {
                            Label(
                                snapshot.isAwaitingCommit ? "Review" : "Finish",
                                systemImage: "checkmark"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: skill.accentHex))
                    }

                    if snapshot.isAwaitingCommit {
                        Label(
                            "The finish time is frozen until this session saves successfully.",
                            systemImage: "lock.shield.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }

                    Button("Discard Session", role: .destructive) {
                        showingDiscardAlert = true
                    }
                    .font(.subheadline)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
            }
            .overlay(alignment: .top) {
                if let levelBanner {
                    LevelUpBanner(skillName: skill.name, banner: levelBanner)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity)
                        )
                }
            }
            .onChange(of: progress.level) { _, newLevel in
                observeLevel(newLevel, skill: skill, snapshot: snapshot)
            }
        }
    }

    private func progressionCard(
        skill: LifeSkill,
        progress: ProgressSnapshot
    ) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("LEVEL \(progress.level)")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                Spacer()
                Text(progress.displayRank.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(SkillingTimeTheme.rankColor(progress.rank))
            }

            SkillProgressBar(
                fraction: progress.fractionComplete,
                accent: Color(hex: skill.accentHex),
                height: 14
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.35),
                value: progress.fractionComplete
            )

            HStack {
                Text("\(progress.currentLevelXP.formatted()) XP")
                Spacer()
                Text(
                    progress.level == 100
                        ? "\(progress.xpRemaining.formatted()) to next star"
                        : "\(progress.xpRemaining.formatted()) to Level \(progress.level + 1)"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func focusGoalCard(
        _ goal: FocusGoalProgress,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("FOCUS GOAL", systemImage: goal.isComplete ? "checkmark.seal.fill" : "scope")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(goal.isComplete ? SkillingTimeTheme.success : accent)
                Spacer()
                if goal.isComplete {
                    Text("COMPLETE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SkillingTimeTheme.success)
                }
            }
            Text(goal.title)
                .font(.headline)
            SkillProgressBar(
                fraction: goal.fractionComplete,
                accent: goal.isComplete ? SkillingTimeTheme.success : accent,
                height: 8
            )
            Text(goal.progressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func observeLevel(
        _ newLevel: Int,
        skill: LifeSkill,
        snapshot: ActiveSessionSnapshot
    ) {
        guard lastObservedLevel > 0, newLevel > lastObservedLevel else {
            lastObservedLevel = max(lastObservedLevel, newLevel)
            return
        }

        let major = [25, 50, 75, 100].contains(newLevel)
        levelBanner = LevelBanner(level: newLevel, isMajor: major)
        lastObservedLevel = newLevel
        Haptics.levelUp(major: major)

        Task {
            await liveActivityCoordinator.synchronize(
                snapshot: sessionController.activeSession ?? snapshot,
                skill: skill,
                baseTotalSeconds: baseTotalSeconds
            )
            await notificationManager.synchronize(
                snapshot: sessionController.activeSession ?? snapshot,
                skill: skill,
                baseTotalSeconds: baseTotalSeconds
            )
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if levelBanner?.level == newLevel {
                withAnimation { levelBanner = nil }
            }
        }
    }

    private func commitSession(
        draft: CompletedSessionDraft,
        countedSeconds: Int,
        note: String,
        skill: LifeSkill
    ) -> String? {
        do {
            let savedOutcome = try SessionCommitService.commit(
                draft: draft,
                countedSeconds: countedSeconds,
                note: note,
                source: .timer,
                skill: skill,
                in: modelContext
            )
            sessionController.markCommitted(sessionID: draft.id)
            outcome = savedOutcome
            finishDraft = nil
            Haptics.sessionComplete()
            return nil
        } catch {
            let localized = error as? LocalizedError
            return [localized?.errorDescription, localized?.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }
}

private struct LevelUpBanner: View {
    let skillName: String
    let banner: LevelBanner

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: banner.isMajor ? "seal.fill" : "chevron.up.2")
                .font(.title2)
                .foregroundStyle(
                    banner.isMajor ? SkillingTimeTheme.gold : SkillingTimeTheme.success
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    banner.isMajor
                        ? "JOURNEY MILESTONE"
                        : "\(skillName.uppercased()) INCREASED"
                )
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(.secondary)
                Text("Level \(banner.level)")
                    .font(.headline)
            }

            Spacer()

            if banner.isMajor {
                Text("Chronicle unlocked")
                    .font(.caption)
                    .foregroundStyle(SkillingTimeTheme.gold)
            }
        }
        .padding(14)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    (banner.isMajor ? SkillingTimeTheme.gold : SkillingTimeTheme.success)
                        .opacity(0.5),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: 7)
        .accessibilityElement(children: .combine)
    }
}

private struct FinishSessionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let skillName: String
    let curveVersion: Int
    let initialSeconds: Int
    let onCancel: () -> Void
    let onSave: (Int, String) -> String?

    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var note = ""
    @State private var saveError: String?

    init(
        skillName: String,
        curveVersion: Int,
        initialSeconds: Int,
        onCancel: @escaping () -> Void,
        onSave: @escaping (Int, String) -> String?
    ) {
        self.skillName = skillName
        self.curveVersion = curveVersion
        self.initialSeconds = initialSeconds
        self.onCancel = onCancel
        self.onSave = onSave
        let editableSeconds = min(
            max(0, initialSeconds),
            SessionCommitService.maximumSessionSeconds
        )
        _hours = State(initialValue: editableSeconds / 3600)
        _minutes = State(initialValue: (editableSeconds % 3600) / 60)
        _seconds = State(initialValue: editableSeconds % 60)
    }

    private var countedSeconds: Int {
        (hours * 3600) + (minutes * 60) + seconds
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Timer", value: DurationText.compact(initialSeconds))
                    Stepper("Counted hours: \(hours)", value: $hours, in: 0...48)
                    Stepper("Counted minutes: \(minutes)", value: $minutes, in: 0...59)
                    Stepper("Counted seconds: \(seconds)", value: $seconds, in: 0...59)
                    LabeledContent(
                        "XP",
                        value: ProgressionEngine.xp(
                            forActiveSeconds: countedSeconds,
                            curveVersion: curveVersion
                        ).formatted()
                    )
                } header: {
                    Text("Time to Count")
                } footer: {
                    if initialSeconds >= 6 * 3600 {
                        Text(
                            "This was a long session. Adjust the counted time if the timer was left running by accident."
                        )
                    } else {
                        Text(
                            "The finish instant is frozen. Time spent reviewing this sheet will not shift the session."
                        )
                    }
                }

                Section("Optional Note") {
                    TextField("What did you do?", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } header: {
                        Text("Not Saved")
                    } footer: {
                        Text("The paused timer remains recoverable. Correct the issue and try again.")
                    }
                }
            }
            .navigationTitle("Finish \(skillName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Skillbook") {
                        if let error = onSave(countedSeconds, note) {
                            saveError = error
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(countedSeconds <= 0)
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

struct SessionSummaryView: View {
    let outcome: SessionOutcome
    let done: () -> Void

    private var accent: Color { Color(hex: outcome.accentHex) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if outcome.chroniclesUnlocked.isEmpty {
                    standardSummary
                } else {
                    ForEach(outcome.chroniclesUnlocked) { entry in
                        MilestoneCeremonyCard(
                            skillName: outcome.skillName,
                            symbolName: outcome.symbolName,
                            accent: accent,
                            entry: entry
                        )
                    }
                    sessionFacts
                }

                levelResult
                focusGoalResult
                unlockedRewards

                if outcome.wasAlreadyCommitted {
                    Label(
                        "This session had already saved successfully. Skilling Time recovered it without creating a duplicate.",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(14)
                }

                Button("Continue", action: done)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
            .padding(20)
        }
        .navigationTitle("Session Complete")
        .navigationBarTitleDisplayMode(.inline)
        .skillingTimeScreenBackground()
        .onAppear {
            if !outcome.chroniclesUnlocked.isEmpty {
                Haptics.levelUp(major: true)
            }
        }
    }

    private var standardSummary: some View {
        VStack(spacing: 18) {
            SkillGlyph(
                symbolName: outcome.symbolName,
                color: accent,
                size: 88,
                rank: outcome.endingProgress.rank
            )

            VStack(spacing: 5) {
                Text("SESSION COMPLETE")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(SkillingTimeTheme.gold)
                Text(outcome.skillName)
                    .font(.largeTitle.bold())
            }

            sessionFacts
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private var levelResult: some View {
        if outcome.levelsGained > 0 {
            VStack(spacing: 4) {
                Text(
                    outcome.levelsGained == 1
                        ? "LEVEL INCREASED"
                        : "+\(outcome.levelsGained) LEVELS"
                )
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(SkillingTimeTheme.success)
                Text("\(outcome.startingProgress.level) → \(outcome.endingProgress.level)")
                    .font(.system(.title, design: .rounded, weight: .bold))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                SkillingTimeTheme.success.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var focusGoalResult: some View {
        if let goal = outcome.focusGoalResult {
            VStack(spacing: 8) {
                Image(systemName: goal.isComplete ? "scope" : "circle.dotted")
                    .font(.title2)
                    .foregroundStyle(
                        goal.isComplete ? SkillingTimeTheme.success : Color.secondary
                    )
                Text(goal.isComplete ? "FOCUS GOAL COMPLETE" : "FOCUS GOAL PROGRESS")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                Text(goal.title)
                    .font(.headline)
                Text(goal.progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                Color.white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var unlockedRewards: some View {
        if !outcome.achievementsUnlocked.isEmpty
            || !outcome.questsCompleted.isEmpty
            || !outcome.capabilitiesUnlocked.isEmpty {
            VStack(spacing: 12) {
                ForEach(outcome.achievementsUnlocked) { achievement in
                    RewardRevealCard(
                        eyebrow: "ACHIEVEMENT UNLOCKED",
                        title: achievement.title,
                        description: achievement.description,
                        systemImage: achievement.systemImage,
                        tint: SkillingTimeTheme.gold
                    )
                }

                ForEach(outcome.questsCompleted) { quest in
                    RewardRevealCard(
                        eyebrow: "QUEST COMPLETE",
                        title: quest.title,
                        description: quest.description,
                        systemImage: quest.systemImage,
                        tint: SkillingTimeTheme.success
                    )
                }

                ForEach(outcome.capabilitiesUnlocked, id: \.rawValue) { capability in
                    RewardRevealCard(
                        eyebrow: "NEW ABILITY",
                        title: capability.title,
                        description: capability.description,
                        systemImage: "wand.and.stars",
                        tint: accent
                    )
                }
            }
        }
    }

    private var sessionFacts: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                MetricCard(
                    title: "Time",
                    value: DurationText.compact(outcome.durationSeconds),
                    systemImage: "timer"
                )
                MetricCard(
                    title: "XP Earned",
                    value: "+\(outcome.xpEarned.formatted())",
                    systemImage: "sparkles"
                )
            }

            if !outcome.note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SESSION NOTE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(outcome.note)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(
                    Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
    }
}

private struct RewardRevealCard: View {
    let eyebrow: String
    let title: String
    let description: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tint.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MilestoneCeremonyCard: View {
    let skillName: String
    let symbolName: String
    let accent: Color
    let entry: ChronicleEntry

    var body: some View {
        ParchmentCard {
            VStack(spacing: 18) {
                Image(systemName: symbolName)
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(accent)

                VStack(spacing: 4) {
                    Text(skillName.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.8)
                    Text(entry.rank.rawValue)
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                    Text("LEVEL \(entry.level)")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                }

                Divider().overlay(SkillingTimeTheme.ink.opacity(0.28))

                Text(entry.chapter)
                    .font(.headline)

                Text(entry.passage)
                    .font(.system(.body, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                VStack(spacing: 5) {
                    Text("NEW MASTERY UNLOCKED")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                    Text(entry.unlockTitle)
                        .font(.headline)
                    Text(entry.unlockDescription)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SkillingTimeTheme.ink.opacity(0.72))
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    SkillingTimeTheme.ink.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(skillName) reached Level \(entry.level), \(entry.rank.rawValue). \(entry.passage)"
        )
    }
}
