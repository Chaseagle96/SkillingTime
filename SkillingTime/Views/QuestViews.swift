import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionController: SessionController
    @Query(sort: \LifeSkill.sortOrder) private var skills: [LifeSkill]
    @Query(sort: \QuestAssignment.periodStart, order: .reverse)
    private var assignments: [QuestAssignment]
    @Query(sort: \ActivityDayLedger.dayStart, order: .reverse)
    private var dayLedgers: [ActivityDayLedger]
    @Query private var skillLedgers: [SkillLedger]
    @Query(sort: \ExpertChallenge.startedAt, order: .reverse)
    private var expertChallenges: [ExpertChallenge]

    @State private var showingActiveSession = false
    @State private var preparationError: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(spacing: 20) {
                    todayHeader(now: context.date)
                    todayMetrics(now: context.date)
                    momentumCard(now: context.date)
                    focusCard(now: context.date)
                    questboard(now: context.date)
                    expertChallengeSection(now: context.date)
                    continueSkillingCard
                    personalBests
                }
                .padding(16)
                .padding(.bottom, 110)
            }
            .refreshable {
                prepareBoard(now: context.date)
            }
            .task(id: ActivityDayLedgerService.identifier(for: context.date)) {
                prepareBoard(now: context.date)
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .skillingTimeScreenBackground()
        .fullScreenCover(isPresented: $showingActiveSession) {
            if let skillID = sessionController.activeSession?.skillID {
                ActiveSessionView(skillID: skillID)
            }
        }
        .alert(
            "Questboard Error",
            isPresented: Binding(
                get: { preparationError != nil },
                set: { if !$0 { preparationError = nil } }
            )
        ) {
            Button("OK") { preparationError = nil }
        } message: {
            Text(preparationError ?? "The Questboard could not be prepared.")
        }
    }

    private func todayHeader(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SKILLING TIME")
                .font(.caption.weight(.bold))
                .tracking(1.7)
                .foregroundStyle(SkillingTimeTheme.gold)
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("What will you level today?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func todayMetrics(now: Date) -> some View {
        let ledger = dayLedgers.first {
            Calendar.current.isDate($0.dayStart, inSameDayAs: now)
        }
        return HStack(spacing: 10) {
            MetricCard(
                title: "Skilling Time",
                value: DurationText.compact(ledger?.totalActiveSeconds ?? 0),
                systemImage: "hourglass"
            )
            MetricCard(
                title: "XP Earned",
                value: (ledger?.xpEarned ?? 0).formatted(),
                systemImage: "sparkles"
            )
        }
    }

    private func momentumCard(now: Date) -> some View {
        let calendar = Calendar.current
        let days = momentumDays(now: now, calendar: calendar)
        let activeCount = days.filter(\.isActive).count
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let weekSeconds = dayLedgers
            .filter { $0.dayStart >= weekStart && $0.dayStart <= now }
            .reduce(0) { $0 + max(0, $1.totalActiveSeconds) }

        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: "Momentum",
                subtitle: "Consistency without a streak to lose"
            )
            HStack(spacing: 8) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        Text(day.date, format: .dateTime.weekday(.narrow))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: day.isActive ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(
                                day.isActive ? SkillingTimeTheme.success : Color.secondary.opacity(0.45)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(day.date.formatted(date: .abbreviated, time: .omitted)), \(day.isActive ? "active" : "rest day")"
                    )
                }
            }
            Text("\(activeCount) active days · \(DurationText.compact(weekSeconds)) this week")
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    @ViewBuilder
    private func focusCard(now: Date) -> some View {
        if let snapshot = sessionController.activeSession,
           let skill = skills.first(where: { $0.id == snapshot.skillID }) {
            let baseSeconds = skillLedgers.first { $0.skillID == skill.id }?.totalActiveSeconds ?? 0
            let sessionSeconds = snapshot.elapsedSeconds(at: now)
            let liveXP = ProgressionEngine.xp(
                forActiveSeconds: baseSeconds + sessionSeconds,
                curveVersion: skill.progressionCurveVersion
            )

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Focus", subtitle: skill.name)
                if let goal = snapshot.focusGoal {
                    let progress = FocusGoalProgress.evaluate(
                        goal: goal,
                        sessionSeconds: sessionSeconds,
                        liveTotalXP: liveXP
                    )
                    Text(progress.title)
                        .font(.headline)
                    SkillProgressBar(
                        fraction: progress.fractionComplete,
                        accent: progress.isComplete
                            ? SkillingTimeTheme.success
                            : Color(hex: skill.accentHex),
                        height: 9
                    )
                    Text(progress.progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Active session")
                        .font(.headline)
                    Text("\(DurationText.compact(sessionSeconds)) · +\(max(0, liveXP - ProgressionEngine.xp(forActiveSeconds: baseSeconds, curveVersion: skill.progressionCurveVersion)).formatted()) XP")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(
                Color(hex: skill.accentHex).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        } else if let skill = recommendedSkill {
            NavigationLink {
                SkillDetailView(skill: skill)
            } label: {
                HStack(spacing: 14) {
                    SkillGlyph(
                        symbolName: skill.symbolName,
                        color: Color(hex: skill.accentHex),
                        size: 48
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SUGGESTED FOCUS")
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(skill.name)
                            .font(.headline)
                        Text("Open this Skill to begin your next session.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(
                    Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func questboard(now: Date) -> some View {
        let statuses = QuestEngine.currentStatuses(assignments: assignments, now: now)
        let daily = statuses.filter { $0.cadence == .daily }
        let weekly = statuses.filter { $0.cadence == .weekly }

        return VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("QUESTBOARD")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(SkillingTimeTheme.gold)
                Text("Optional paths shaped by your Skillbook")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            questSection(title: "Today", quests: daily)
            questSection(title: "This Week", quests: weekly)

            Text("Assignments stay fixed for their period. Missing one never removes XP, Momentum, or an earned reward.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func questSection(title: String, quests: [QuestStatus]) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(quests.filter(\.isComplete).count) / \(quests.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ForEach(quests) { quest in
                QuestCard(quest: quest)
            }
        }
    }

    @ViewBuilder
    private func expertChallengeSection(now: Date) -> some View {
        let active = expertChallenges.filter { $0.isActive(at: now) }
        if !active.isEmpty {
            VStack(spacing: 10) {
                SectionTitle(
                    title: "Expert Undertakings",
                    subtitle: "Long-form challenges chosen from Expert Skills"
                )
                ForEach(active) { challenge in
                    let skill = skills.first { $0.id == challenge.skillID }
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label(challenge.title, systemImage: challenge.systemImage)
                                .font(.headline)
                            Spacer()
                            Text(skill?.name ?? "Skill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: challenge.fractionComplete)
                            .tint(SkillingTimeTheme.gold)
                        HStack {
                            Text(challenge.progressLabel)
                            Spacer()
                            Text(challenge.endsAt, format: .dateTime.month(.abbreviated).day())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(15)
                    .background(
                        SkillingTimeTheme.gold.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var continueSkillingCard: some View {
        if let snapshot = sessionController.activeSession,
           let skill = skills.first(where: { $0.id == snapshot.skillID }) {
            Button {
                showingActiveSession = true
            } label: {
                HStack(spacing: 13) {
                    SkillGlyph(
                        symbolName: skill.symbolName,
                        color: Color(hex: skill.accentHex),
                        size: 46
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CONTINUE SKILLING")
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(skill.name)
                            .font(.headline)
                        Text(snapshot.isPaused ? "Paused" : "Session in progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Resume", systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(hex: skill.accentHex))
                }
                .padding(16)
                .background(
                    Color(hex: skill.accentHex).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var personalBests: some View {
        let longestLedger = skillLedgers.max {
            $0.longestSessionSeconds < $1.longestSessionSeconds
        }
        let longestSkillName = longestLedger.flatMap { ledger in
            skills.first { $0.id == ledger.skillID }?.name
        } ?? "Session"
        let bestDay = dayLedgers.max { $0.totalActiveSeconds < $1.totalActiveSeconds }
        let bestXPDay = dayLedgers.max { $0.xpEarned < $1.xpEarned }
        let bestWeek = bestWeekSeconds

        return VStack(spacing: 12) {
            SectionTitle(
                title: "Personal Bests",
                subtitle: "History worth remembering"
            )
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                MetricCard(
                    title: "Longest \(longestSkillName)",
                    value: DurationText.compact(longestLedger?.longestSessionSeconds ?? 0),
                    systemImage: "stopwatch.fill"
                )
                MetricCard(
                    title: "Best Day",
                    value: DurationText.compact(bestDay?.totalActiveSeconds ?? 0),
                    systemImage: "sun.max.fill"
                )
                MetricCard(
                    title: "Highest XP Day",
                    value: (bestXPDay?.xpEarned ?? 0).formatted(),
                    systemImage: "sparkles"
                )
                MetricCard(
                    title: "Best Week",
                    value: DurationText.compact(bestWeek),
                    systemImage: "calendar.badge.checkmark"
                )
            }
        }
    }

    private var recommendedSkill: LifeSkill? {
        let statuses = QuestEngine.currentStatuses(assignments: assignments)
        if let targetID = statuses.first(where: {
            !$0.isComplete && $0.targetSkillID != nil
        })?.targetSkillID,
           let skill = skills.first(where: { $0.id == targetID && !$0.isArchived }) {
            return skill
        }

        return skills
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let lhsDate = skillLedgers.first { $0.skillID == lhs.id }?.latestSessionAt
                let rhsDate = skillLedgers.first { $0.skillID == rhs.id }?.latestSessionAt
                if lhsDate != rhsDate {
                    return (lhsDate ?? .distantPast) < (rhsDate ?? .distantPast)
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .first
    }

    private var bestWeekSeconds: Int {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: dayLedgers) { ledger in
            calendar.dateInterval(of: .weekOfYear, for: ledger.dayStart)?.start
                ?? calendar.startOfDay(for: ledger.dayStart)
        }
        return grouped.values.map {
            $0.reduce(0) { $0 + max(0, $1.totalActiveSeconds) }
        }.max() ?? 0
    }

    private func momentumDays(now: Date, calendar: Calendar) -> [MomentumDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let isActive = dayLedgers.contains {
                $0.totalActiveSeconds > 0 && calendar.isDate($0.dayStart, inSameDayAs: date)
            }
            return MomentumDay(date: date, isActive: isActive)
        }
    }

    private func prepareBoard(now: Date = .now) {
        do {
            try ActivityDayLedgerService.rebuildIfNeeded(in: modelContext, now: now)
            _ = try QuestBoardService.prepareCurrentBoard(in: modelContext, now: now)
            preparationError = nil
        } catch {
            preparationError = error.localizedDescription
        }
    }
}

private struct MomentumDay: Identifiable {
    let date: Date
    let isActive: Bool

    var id: Date { date }
}

private struct QuestCard: View {
    let quest: QuestStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            (quest.isComplete
                                ? SkillingTimeTheme.success
                                : SkillingTimeTheme.gold).opacity(0.12)
                        )
                    Image(systemName: quest.isComplete ? "checkmark.seal.fill" : quest.systemImage)
                        .font(.title3)
                        .foregroundStyle(
                            quest.isComplete
                                ? SkillingTimeTheme.success
                                : SkillingTimeTheme.gold
                        )
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(quest.title)
                        .font(.headline)
                    Text(quest.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            SkillProgressBar(
                fraction: quest.fractionComplete,
                accent: quest.isComplete
                    ? SkillingTimeTheme.success
                    : SkillingTimeTheme.gold,
                height: 8
            )

            HStack {
                Text(quest.progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if quest.isComplete {
                    Text("COMPLETE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(SkillingTimeTheme.success)
                }
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            if quest.isComplete {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(SkillingTimeTheme.success.opacity(0.28), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(quest.isComplete ? "Complete" : quest.progressLabel)
    }
}
