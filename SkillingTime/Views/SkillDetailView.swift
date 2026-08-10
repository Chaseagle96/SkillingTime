import SwiftData
import SwiftUI

struct SkillDetailView: View {
    @EnvironmentObject private var sessionController: SessionController
    @Query private var sessions: [SkillSession]
    @Query private var chronicleUnlocks: [ChronicleUnlock]
    @Query private var specializations: [SkillSpecialization]

    let skill: LifeSkill

    @State private var showingActiveSession = false
    @State private var showingManualEntry = false
    @State private var showingFocusGoal = false
    @State private var showingEditSkill = false
    @State private var showingSpecialization = false
    @State private var sessionOutcome: SessionOutcome?
    @State private var editingSession: SkillSession?

    init(skill: LifeSkill) {
        self.skill = skill
        let skillID = skill.id
        _sessions = Query(
            filter: #Predicate<SkillSession> { session in
                session.skillID == skillID
            },
            sort: \SkillSession.endedAt,
            order: .reverse
        )
        _chronicleUnlocks = Query(
            filter: #Predicate<ChronicleUnlock> { unlock in
                unlock.skillID == skillID
            }
        )
        _specializations = Query(
            filter: #Predicate<SkillSpecialization> { specialization in
                specialization.skillID == skillID
            }
        )
    }

    private var statistics: SkillStatistics {
        SessionAnalytics.statistics(for: skill.id, sessions: sessions)
    }

    private var progress: ProgressSnapshot {
        let xp = ProgressionEngine.xp(
            forActiveSeconds: statistics.totalSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        return ProgressionEngine.progress(
            forTotalXP: xp,
            curveVersion: skill.progressionCurveVersion
        )
    }

    private var accent: Color { Color(hex: skill.accentHex) }

    private var hasFocusGoals: Bool {
        progress.level >= 25 || chronicleUnlocks.contains { $0.milestoneLevel == 25 }
    }

    private var specialization: SkillSpecialization? { specializations.first }

    private var hasSpecializationCapability: Bool {
        progress.level >= 50 || chronicleUnlocks.contains { $0.milestoneLevel == 50 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                if skill.isArchived {
                    retiredNotice
                } else {
                    primaryActions
                }
                statisticsGrid
                recentHistory
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditSkill = true
                    } label: {
                        Label("Edit Skill", systemImage: "pencil")
                    }
                    if hasSpecializationCapability {
                        Button {
                            showingSpecialization = true
                        } label: {
                            Label(
                                specialization == nil
                                    ? "Choose Specialization"
                                    : "Edit Specialization",
                                systemImage: "signature"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Skill options")
            }
        }
        .fullScreenCover(isPresented: $showingActiveSession) {
            ActiveSessionView(skillID: skill.id)
        }
        .sheet(isPresented: $showingFocusGoal) {
            FocusGoalPickerView(skill: skill, progress: progress) { goal in
                startSession(focusGoal: goal)
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualSessionView(skill: skill) { outcome in
                sessionOutcome = outcome
            }
        }
        .sheet(item: $editingSession) { session in
            SessionEditorView(session: session)
        }
        .sheet(isPresented: $showingEditSkill) {
            EditSkillView(skill: skill)
        }
        .sheet(isPresented: $showingSpecialization) {
            SpecializationEditorView(
                skill: skill,
                existingSpecialization: specialization
            )
        }
        .sheet(item: $sessionOutcome) { outcome in
            NavigationStack {
                SessionSummaryView(outcome: outcome) {
                    sessionOutcome = nil
                }
            }
        }
        .skillingTimeScreenBackground()
    }

    private var hero: some View {
        VStack(spacing: 18) {
            SkillGlyph(
                symbolName: skill.symbolName,
                color: accent,
                size: 88,
                rank: progress.rank
            )

            VStack(spacing: 5) {
                Text(skill.name.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(accent)
                Text("Level \(progress.level)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                HStack(spacing: 6) {
                    Text(progress.displayRank)
                    if skill.isArchived {
                        Text("· Retired")
                    }
                }
                .font(.headline)
                .foregroundStyle(SkillingTimeTheme.rankColor(progress.rank))
                if let specialization {
                    Text(specialization.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SkillingTimeTheme.gold)
                }
            }

            VStack(spacing: 8) {
                SkillProgressBar(
                    fraction: progress.fractionComplete,
                    accent: accent,
                    height: 12
                )
                HStack {
                    Text("\(progress.currentLevelXP.formatted()) / \(progress.nextLevelXP.formatted()) XP")
                    Spacer()
                    Text(
                        progress.level == 100
                            ? "to next Mastery star"
                            : "\(progress.xpRemaining.formatted()) remaining"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.12), Color.white.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    SkillingTimeTheme.rankColor(progress.rank).opacity(0.28),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
    }

    private var retiredNotice: some View {
        Label(
            "This Skill is retired. Its levels, achievements, Chronicle, and recorded time remain part of your lifetime character.",
            systemImage: "archivebox.fill"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var primaryActions: some View {
        VStack(spacing: 10) {
            Button {
                beginOrResumeSession()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(isAnotherSkillActive)

            Button {
                showingManualEntry = true
            } label: {
                Label("Log Past Session", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            if hasFocusGoals {
                Label("Apprentice ability unlocked: Focus Goals", systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(accent)
            }

            if hasSpecializationCapability {
                Button {
                    showingSpecialization = true
                } label: {
                    Label(
                        specialization == nil
                            ? "Choose Journeyman Specialization"
                            : "Specialization: \(specialization?.title ?? "")",
                        systemImage: "signature"
                    )
                }
                .buttonStyle(.bordered)
                .tint(SkillingTimeTheme.gold)
            }

            if isAnotherSkillActive {
                Text("Finish or discard the active Skill session before starting another.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var statisticsGrid: some View {
        VStack(spacing: 12) {
            SectionTitle(
                title: "Record",
                subtitle: "Everything here is derived from completed sessions."
            )

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                MetricCard(
                    title: "Total Time",
                    value: DurationText.compact(statistics.totalSeconds),
                    systemImage: "hourglass"
                )
                MetricCard(
                    title: "Total XP",
                    value: progress.totalXP.formatted(),
                    systemImage: "sparkles"
                )
                MetricCard(
                    title: "Sessions",
                    value: statistics.sessionCount.formatted(),
                    systemImage: "checkmark.seal"
                )
                MetricCard(
                    title: "Active Days",
                    value: statistics.activeDayCount.formatted(),
                    systemImage: "calendar"
                )
                MetricCard(
                    title: "Average",
                    value: DurationText.compact(statistics.averageSeconds),
                    systemImage: "chart.bar.fill"
                )
                MetricCard(
                    title: "Longest",
                    value: DurationText.compact(statistics.longestSeconds),
                    systemImage: "timer"
                )
            }
        }
    }

    private var recentHistory: some View {
        VStack(spacing: 12) {
            SectionTitle(
                title: "Recent History",
                subtitle: sessions.isEmpty ? nil : "Tap a session to inspect or correct it"
            )

            if sessions.isEmpty {
                EmptyStateCard(
                    systemImage: "clock.badge.questionmark",
                    title: "No sessions yet",
                    message: "Start the timer or log past activity to begin this Skill's history."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.prefix(20).enumerated()), id: \.element.id) { index, session in
                        Button {
                            editingSession = session
                        } label: {
                            SessionHistoryRow(session: session)
                        }
                        .buttonStyle(.plain)

                        if index < min(sessions.count, 20) - 1 {
                            Divider().opacity(0.20)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
        }
    }

    private var isAnotherSkillActive: Bool {
        guard let active = sessionController.activeSession else { return false }
        return active.skillID != skill.id
    }

    private var primaryActionTitle: String {
        sessionController.activeSession?.skillID == skill.id
            ? "Return to Session"
            : "Start Session"
    }

    private var primaryActionIcon: String {
        sessionController.activeSession?.skillID == skill.id ? "timer" : "play.fill"
    }

    private func beginOrResumeSession() {
        if sessionController.activeSession?.skillID == skill.id {
            showingActiveSession = true
            return
        }
        guard sessionController.activeSession == nil else { return }

        if hasFocusGoals {
            showingFocusGoal = true
        } else {
            startSession(focusGoal: nil)
        }
    }

    private func startSession(focusGoal: SessionFocusGoal?) {
        guard sessionController.start(skillID: skill.id, focusGoal: focusGoal) else { return }
        showingFocusGoal = false
        showingActiveSession = true
    }
}

private struct SessionHistoryRow: View {
    let session: SkillSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.source == .manual ? "square.and.pencil" : "timer")
                .frame(width: 30, height: 30)
                .foregroundStyle(SkillingTimeTheme.gold)
                .background(SkillingTimeTheme.gold.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    session.endedAt,
                    format: .dateTime.month(.abbreviated).day().hour().minute()
                )
                .font(.subheadline.weight(.medium))
                if !session.note.isEmpty {
                    Text(session.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationText.compact(session.activeSeconds))
                    .font(.subheadline.weight(.semibold))
                Text(session.source == .manual ? "MANUAL" : "TIMER")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens session details and correction controls")
    }
}

private enum FocusGoalChoice: String, CaseIterable, Identifiable {
    case noGoal
    case thirtyMinutes
    case sevenHundredFiftyXP
    case nextThreshold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noGoal: "No goal"
        case .thirtyMinutes: "Practice for 30 minutes"
        case .sevenHundredFiftyXP: "Earn 750 XP"
        case .nextThreshold: "Reach the next progression threshold"
        }
    }

    var systemImage: String {
        switch self {
        case .noGoal: "circle"
        case .thirtyMinutes: "timer"
        case .sevenHundredFiftyXP: "sparkles"
        case .nextThreshold: "chevron.up.2"
        }
    }
}

private struct FocusGoalPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let skill: LifeSkill
    let progress: ProgressSnapshot
    let onStart: (SessionFocusGoal?) -> Void

    @State private var selection = FocusGoalChoice.thirtyMinutes

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "Focus Goals were earned when \(skill.name) reached Apprentice at Level 25.",
                        systemImage: "seal.fill"
                    )
                    .foregroundStyle(Color(hex: skill.accentHex))
                }

                Section("Session Goal") {
                    ForEach(FocusGoalChoice.allCases) { choice in
                        Button {
                            selection = choice
                            Haptics.selection()
                        } label: {
                            HStack {
                                Label(choice.title, systemImage: choice.systemImage)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selection == choice {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(hex: skill.accentHex))
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("Focus Goals do not change XP. They provide a clear destination for this session and remain nonpunitive if unfinished.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Begin \(skill.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart(makeGoal())
                    }
                }
            }
        }
    }

    private func makeGoal() -> SessionFocusGoal? {
        switch selection {
        case .noGoal:
            nil
        case .thirtyMinutes:
            .duration(seconds: 30 * 60, startingTotalXP: progress.totalXP)
        case .sevenHundredFiftyXP:
            .xp(amount: 750, startingTotalXP: progress.totalXP)
        case .nextThreshold:
            .progression(
                targetTotalXP: ProgressionEngine.nextThresholdXP(
                    after: progress,
                    curveVersion: skill.progressionCurveVersion
                ),
                startingTotalXP: progress.totalXP
            )
        }
    }
}

private struct SpecializationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let skill: LifeSkill
    let existingSpecialization: SkillSpecialization?

    @State private var title: String
    @State private var saveError: String?

    init(
        skill: LifeSkill,
        existingSpecialization: SkillSpecialization?
    ) {
        self.skill = skill
        self.existingSpecialization = existingSpecialization
        _title = State(initialValue: existingSpecialization?.title ?? "")
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestions: [String] {
        let identity = "\(skill.name) \(skill.category)".lowercased()
        if identity.contains("cook") {
            return ["Home Cook", "Bread Maker", "Meal Prepper", "Pitmaster"]
        }
        if identity.contains("read") || identity.contains("learn") {
            return ["Bookkeeper", "Researcher", "Lifelong Learner", "Scholar"]
        }
        if identity.contains("exercise") || identity.contains("fitness") {
            return ["Endurance Builder", "Strength Seeker", "Daily Mover", "Athlete"]
        }
        return ["Practitioner", "Craftsperson", "Specialist", "Dedicated Hand"]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        SkillGlyph(
                            symbolName: skill.symbolName,
                            color: Color(hex: skill.accentHex),
                            size: 62,
                            rank: .journeyman
                        )
                        Text(skill.name)
                            .font(.headline)
                        Text(trimmedTitle.isEmpty ? "Journeyman" : "Journeyman · \(trimmedTitle)")
                            .font(.subheadline)
                            .foregroundStyle(SkillingTimeTheme.gold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("Custom Title") {
                    TextField("Specialization", text: $title)
                        .textInputAutocapitalization(.words)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > 40 {
                                title = String(newValue.prefix(40))
                            }
                        }
                    Text("Identity only. Specializations never change XP or Quest rewards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Suggestions") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            title = suggestion
                            Haptics.selection()
                        }
                    }
                }

                if let saveError {
                    Section("Not Saved") {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if existingSpecialization != nil {
                    Section {
                        Button("Remove Specialization", role: .destructive) {
                            removeSpecialization()
                        }
                    }
                }
            }
            .navigationTitle("Specialization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let existingSpecialization {
            existingSpecialization.title = trimmedTitle
            existingSpecialization.chosenAt = .now
        } else {
            modelContext.insert(
                SkillSpecialization(skillID: skill.id, title: trimmedTitle)
            )
        }

        do {
            try modelContext.save()
            Haptics.sessionComplete()
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }

    private func removeSpecialization() {
        guard let existingSpecialization else { return }
        modelContext.delete(existingSpecialization)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

private struct ManualSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let skill: LifeSkill
    let onSaved: (SessionOutcome) -> Void

    @State private var date = Date.now
    @State private var hours = 0
    @State private var minutes = 30
    @State private var note = ""
    @State private var saveError: String?

    private var durationSeconds: Int { (hours * 3600) + (minutes * 60) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Ended", selection: $date, in: ...Date.now)
                } header: {
                    Text("When")
                } footer: {
                    Text("Daily and weekly records credit a session when it ended.")
                }

                Section("Duration") {
                    Stepper("Hours: \(hours)", value: $hours, in: 0...24)
                    Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59)
                    LabeledContent(
                        "Base XP",
                        value: ProgressionEngine.xp(
                            forActiveSeconds: durationSeconds,
                            curveVersion: skill.progressionCurveVersion
                        ).formatted()
                    )
                }

                Section("Optional Note") {
                    TextField("What did you do?", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Text("Manual sessions earn the same XP as timed sessions. Skillbook is a record of honest effort, not a policing system.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let saveError {
                    Section("Not Saved") {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Log \(skill.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(durationSeconds <= 0)
                }
            }
        }
    }

    private func save() {
        let draft = CompletedSessionDraft(
            id: UUID(),
            skillID: skill.id,
            startedAt: date.addingTimeInterval(TimeInterval(-durationSeconds)),
            endedAt: date,
            activeSeconds: durationSeconds,
            focusGoal: nil,
            shouldResumeOnCancel: false
        )

        do {
            let outcome = try SessionCommitService.commit(
                draft: draft,
                countedSeconds: durationSeconds,
                note: note,
                source: .manual,
                skill: skill,
                in: modelContext
            )
            dismiss()
            DispatchQueue.main.async {
                onSaved(outcome)
            }
        } catch {
            let localized = error as? LocalizedError
            saveError = [localized?.errorDescription, localized?.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }
}

private struct SessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LifeSkill.sortOrder) private var skills: [LifeSkill]
    @Query(sort: \SkillSession.endedAt) private var sessions: [SkillSession]
    @Query private var achievementUnlocks: [AchievementUnlock]
    @Query private var chronicleUnlocks: [ChronicleUnlock]

    let session: SkillSession

    @State private var endedAt: Date
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var note: String
    @State private var saveError: String?
    @State private var showingUpdateConfirmation = false
    @State private var showingDeleteConfirmation = false

    init(session: SkillSession) {
        self.session = session
        _endedAt = State(initialValue: session.endedAt)
        _hours = State(initialValue: session.activeSeconds / 3600)
        _minutes = State(initialValue: (session.activeSeconds % 3600) / 60)
        _seconds = State(initialValue: session.activeSeconds % 60)
        _note = State(initialValue: session.note)
    }

    private var durationSeconds: Int {
        (hours * 3600) + (minutes * 60) + seconds
    }

    private var impact: SessionMutationImpact? {
        try? SessionCommitService.previewUpdate(
            session: session,
            endedAt: endedAt,
            activeSeconds: durationSeconds,
            note: note,
            skills: skills,
            sessions: sessions,
            existingRewardIdentifiers: rewardIdentifiers
        )
    }

    private var deletionImpact: SessionMutationImpact? {
        try? SessionCommitService.previewDeletion(
            session: session,
            skills: skills,
            sessions: sessions,
            existingRewardIdentifiers: rewardIdentifiers
        )
    }

    private var rewardIdentifiers: Set<String> {
        Set(achievementUnlocks.map(\.id) + chronicleUnlocks.map(\.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    DatePicker("Ended", selection: $endedAt, in: ...Date.now)
                    Stepper("Hours: \(hours)", value: $hours, in: 0...48)
                    Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59)
                    Stepper("Seconds: \(seconds)", value: $seconds, in: 0...59)
                }

                Section("Note") {
                    TextField("What did you do?", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let impact {
                    impactSection(impact)
                }

                if let saveError {
                    Section("Not Saved") {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Delete Session", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } footer: {
                    if let deletionImpact, !deletionImpact.rewardsPreserved.isEmpty {
                        Text(
                            "Deleting this session will not erase earned rewards: \(deletionImpact.rewardsPreserved.joined(separator: ", "))."
                        )
                    }
                }
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        showingUpdateConfirmation = true
                    }
                    .disabled(durationSeconds <= 0 || impact == nil)
                }
            }
            .alert("Apply this correction?", isPresented: $showingUpdateConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Apply") { saveChanges() }
            } message: {
                if let impact {
                    Text(confirmationMessage(for: impact))
                }
            }
            .alert("Delete this session?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteSession() }
            } message: {
                if let deletionImpact {
                    Text(confirmationMessage(for: deletionImpact))
                } else {
                    Text("This removes the session from authoritative history.")
                }
            }
        }
    }

    private func impactSection(_ impact: SessionMutationImpact) -> some View {
        Section {
            LabeledContent(
                "Duration",
                value: "\(DurationText.compact(impact.beforeDurationSeconds)) → \(DurationText.compact(impact.afterDurationSeconds))"
            )
            LabeledContent(
                "Level",
                value: "\(impact.beforeProgress.level) → \(impact.afterProgress.level)"
            )
            LabeledContent(
                "Total XP",
                value: "\(impact.beforeProgress.totalXP.formatted()) → \(impact.afterProgress.totalXP.formatted())"
            )
            if !impact.rewardsAdded.isEmpty {
                Label(
                    "Would unlock: \(impact.rewardsAdded.joined(separator: ", "))",
                    systemImage: "sparkles"
                )
                .foregroundStyle(SkillingTimeTheme.success)
            }
            if !impact.rewardsPreserved.isEmpty {
                Label(
                    "Remains earned: \(impact.rewardsPreserved.joined(separator: ", "))",
                    systemImage: "checkmark.shield.fill"
                )
                .foregroundStyle(SkillingTimeTheme.gold)
            }
        } header: {
            Text("Progression Impact")
        } footer: {
            Text("XP and levels follow corrected time. Earned rewards remain part of your history.")
        }
    }

    private func confirmationMessage(for impact: SessionMutationImpact) -> String {
        var parts = [
            "\(impact.skillName) will change from Level \(impact.beforeProgress.level) to Level \(impact.afterProgress.level)."
        ]
        if !impact.rewardsPreserved.isEmpty {
            parts.append("Previously earned rewards remain unlocked.")
        }
        if !impact.rewardsAdded.isEmpty {
            parts.append("This will unlock \(impact.rewardsAdded.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    private func saveChanges() {
        do {
            _ = try SessionCommitService.update(
                session: session,
                endedAt: endedAt,
                activeSeconds: durationSeconds,
                note: note,
                in: modelContext
            )
            Haptics.sessionComplete()
            dismiss()
        } catch {
            let localized = error as? LocalizedError
            saveError = [localized?.errorDescription, localized?.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }

    private func deleteSession() {
        do {
            _ = try SessionCommitService.delete(session: session, in: modelContext)
            Haptics.selection()
            dismiss()
        } catch {
            let localized = error as? LocalizedError
            saveError = [localized?.errorDescription, localized?.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }
}
