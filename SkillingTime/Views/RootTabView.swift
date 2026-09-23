import SwiftData
import SwiftUI

/// Single owner of the full-screen active session. Views ask it to present
/// instead of attaching their own covers, so a deep link, a notification tap, and
/// a Skill screen can never stack two timer screens.
@MainActor
final class ActiveSessionPresenter: ObservableObject {
    struct Presentation: Identifiable, Equatable {
        let id: UUID
    }

    @Published var presentation: Presentation?

    func present(skillID: UUID) {
        guard presentation?.id != skillID else { return }
        presentation = Presentation(id: skillID)
    }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var sessionController: SessionController
    @EnvironmentObject private var liveActivityCoordinator: LiveActivityCoordinator
    @EnvironmentObject private var notificationManager: ProgressionNotificationManager
    @Query(sort: \LifeSkill.sortOrder) private var skills: [LifeSkill]
    @Query private var ledgers: [SkillLedger]
    @Query(sort: \QuestAssignment.periodStart, order: .reverse)
    private var questAssignments: [QuestAssignment]

    @StateObject private var presenter = ActiveSessionPresenter()
    @State private var selectedTab = 0
    @State private var persistenceError: String?
    @State private var ambientSyncTask: Task<Void, Never>?

    private var activeSkill: LifeSkill? {
        guard let skillID = sessionController.activeSession?.skillID else { return nil }
        return skills.first { $0.id == skillID }
    }

    private var activeBaseSeconds: Int {
        guard let skillID = sessionController.activeSession?.skillID else { return 0 }
        return ledgers.first { $0.skillID == skillID }?.totalActiveSeconds ?? 0
    }

    private var activeQuestAssignment: QuestAssignment? {
        guard let skillID = sessionController.activeSession?.skillID else { return nil }
        return questAssignments
            .filter {
                QuestEngine.isCurrent($0)
                    && $0.completedAt == nil
                    && ($0.targetSkillID == nil || $0.targetSkillID == skillID)
                    && isLiveQuest($0)
            }
            .sorted {
                let lhsPriority = questLivePriority($0)
                let rhsPriority = questLivePriority($1)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return $0.slot < $1.slot
            }
            .first
    }

    var body: some View {
        Group {
            if #available(iOS 26.1, *) {
                toggleableNativeAccessoryTabs
            } else if #available(iOS 26.0, *) {
                nativeAccessoryTabs
            } else {
                fallbackAccessoryTabs
            }
        }
        .animation(
            SkillingTimeMotion.animation(
                SkillingTimeMotion.responsive,
                reduceMotion: reduceMotion
            ),
            value: sessionController.activeSession != nil
        )
        .fullScreenCover(item: $presenter.presentation) { presentation in
            ActiveSessionView(skillID: presentation.id)
        }
        .onChange(of: selectedTab) { _, _ in
            Haptics.selection()
        }
        .onOpenURL(perform: handleDeepLink)
        .task {
            var preparationFailures: [String] = []
            do {
                try seedBuiltInSkillsIfNeeded()
            } catch {
                preparationFailures.append("Skill setup: \(error.localizedDescription)")
            }
            do {
                try RewardBackfillService.reconcileAll(in: modelContext)
            } catch {
                preparationFailures.append("Reward history: \(error.localizedDescription)")
            }
            do {
                try SkillLedgerService.rebuildIfNeeded(in: modelContext)
            } catch {
                preparationFailures.append("Progress ledger: \(error.localizedDescription)")
            }
            do {
                try ActivityDayLedgerService.rebuildIfNeeded(in: modelContext)
            } catch {
                preparationFailures.append("Daily activity ledger: \(error.localizedDescription)")
            }
            do {
                try CharacterProgressionService.prepare(in: modelContext)
            } catch {
                preparationFailures.append("Character Paths: \(error.localizedDescription)")
            }
            do {
                _ = try QuestBoardService.prepareCurrentBoard(in: modelContext)
            } catch {
                preparationFailures.append("Questboard: \(error.localizedDescription)")
            }
            if !preparationFailures.isEmpty {
                persistenceError = "Skilling Time could not fully prepare its persistent history. "
                    + preparationFailures.joined(separator: " ")
            }
            if let storageError = sessionController.storageErrorMessage {
                persistenceError = storageError
            }
            clearRecoveredCommittedTimer()
            handleOpenedNotification(notificationManager.openedSessionID)
            synchronizeAmbientSessionSoon()
        }
        .onChange(of: sessionController.activeSession) { _, _ in
            synchronizeAmbientSessionSoon()
        }
        .onChange(of: ledgerFingerprints) { _, _ in
            synchronizeAmbientSessionSoon()
        }
        .onChange(of: skillFingerprints) { _, _ in
            synchronizeAmbientSessionSoon()
        }
        .onChange(of: questFingerprints) { _, _ in
            synchronizeAmbientSessionSoon()
        }
        .onChange(of: notificationManager.alertsEnabled) { _, _ in
            synchronizeAmbientSessionSoon()
        }
        .onChange(of: sessionController.ambientSyncRequest) { _, _ in
            synchronizeAmbientSessionSoon()
        }
        .onChange(of: notificationManager.openedSessionID) { _, sessionID in
            handleOpenedNotification(sessionID)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            sessionController.refreshFromSharedStorage()
            clearRecoveredCommittedTimer()
            do {
                _ = try QuestBoardService.prepareCurrentBoard(in: modelContext)
            } catch {
                persistenceError = "The Questboard could not refresh. \(error.localizedDescription)"
            }
            synchronizeAmbientSessionSoon()
        }
        .onChange(of: sessionController.storageErrorMessage) { _, message in
            if let message {
                persistenceError = message
            }
        }
        .onChange(of: liveActivityCoordinator.lastErrorMessage) { _, message in
            if let message {
                persistenceError = message
            }
        }
        .alert(
            "Skilling Time Error",
            isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )
        ) {
            Button("OK") { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "The requested change could not be completed.")
        }
        .environmentObject(presenter)
        .preferredColorScheme(.dark)
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }
            .tag(0)

            NavigationStack {
                SkillbookView()
            }
            .tabItem { Label("Skills", systemImage: "square.grid.2x2.fill") }
            .tag(1)

            NavigationStack {
                ChronicleRootView()
            }
            .tabItem { Label("Chronicle", systemImage: "scroll.fill") }
            .tag(2)

            NavigationStack {
                CharacterView()
            }
            .tabItem { Label("Character", systemImage: "person.crop.circle.fill") }
            .tag(3)
        }
        .tint(SkillingTimeTheme.gold)
    }

    @available(iOS 26.0, *)
    private var nativeAccessoryTabs: some View {
        tabView
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                nativeSessionAccessory
                    .padding(.horizontal, 8)
            }
    }

    @available(iOS 26.1, *)
    private var toggleableNativeAccessoryTabs: some View {
        tabView
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(
                isEnabled: sessionController.activeSession != nil
            ) {
                nativeSessionAccessory
                    .padding(.horizontal, 8)
            }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var nativeSessionAccessory: some View {
        if let snapshot = sessionController.activeSession,
           let skill = activeSkill {
            NativeSessionAccessory(
                skill: skill,
                snapshot: snapshot,
                baseTotalSeconds: activeBaseSeconds
            ) {
                openActiveSession(skillID: skill.id)
            }
        }
    }

    private var fallbackAccessoryTabs: some View {
        ZStack(alignment: .bottom) {
            tabView
            sessionAccessory
                .padding(.horizontal, 12)
                .padding(.bottom, 54)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
        }
    }

    @ViewBuilder
    private var sessionAccessory: some View {
        if let snapshot = sessionController.activeSession,
           let skill = activeSkill {
            MiniSessionBar(
                skill: skill,
                snapshot: snapshot,
                baseTotalSeconds: activeBaseSeconds
            ) {
                openActiveSession(skillID: skill.id)
            }
        }
    }

    private var ledgerFingerprints: [LedgerFingerprint] {
        ledgers.map {
            LedgerFingerprint(
                skillID: $0.skillID,
                totalActiveSeconds: $0.totalActiveSeconds,
                sessionCount: $0.sessionCount
            )
        }
        .sorted { $0.skillID.uuidString < $1.skillID.uuidString }
    }

    private var skillFingerprints: [SkillFingerprint] {
        skills.map {
            SkillFingerprint(
                id: $0.id,
                name: $0.name,
                symbolName: $0.symbolName,
                accentHex: $0.accentHex,
                curveVersion: $0.progressionCurveVersion
            )
        }
    }

    private var questFingerprints: [QuestFingerprint] {
        questAssignments.map {
            QuestFingerprint(
                id: $0.id,
                currentValue: $0.currentValue,
                targetValue: $0.targetValue,
                completedAt: $0.completedAt,
                retiredAt: $0.retiredAt
            )
        }
        .sorted { $0.id < $1.id }
    }

    private func openActiveSession(skillID: UUID) {
        presenter.present(skillID: skillID)
    }

    /// If the app stopped after SwiftData saved a session but before the timer was
    /// cleared, the timer comes back "awaiting commit". Its UUID is already in
    /// history, so clear it here rather than letting Cancel resume a saved session.
    private func clearRecoveredCommittedTimer() {
        guard let snapshot = sessionController.activeSession,
              snapshot.isAwaitingCommit else { return }
        let sessionID = snapshot.id
        let descriptor = FetchDescriptor<SkillSession>(
            predicate: #Predicate<SkillSession> { session in
                session.id == sessionID
            }
        )
        if let count = try? modelContext.fetchCount(descriptor), count > 0 {
            sessionController.markCommitted(sessionID: sessionID)
        }
    }

    private func handleOpenedNotification(_ sessionID: UUID?) {
        guard let sessionID else { return }
        notificationManager.consumeOpenedSession()
        guard let snapshot = sessionController.activeSession,
              snapshot.id == sessionID else { return }
        openActiveSession(skillID: snapshot.skillID)
    }

    private func handleDeepLink(_ url: URL) {
        guard ["skillingtime", "skillbook"].contains(url.scheme?.lowercased() ?? ""),
              url.host == "session",
              let snapshot = sessionController.activeSession else { return }

        let components = url.pathComponents.filter { $0 != "/" }
        guard let identifier = components.first,
              let sessionID = UUID(uuidString: identifier),
              sessionID == snapshot.id else { return }

        if components.dropFirst().first == "finish" {
            _ = sessionController.requestFinish()
        }
        openActiveSession(skillID: snapshot.skillID)
    }

    /// Syncs run one at a time in request order. Each run reads the latest state,
    /// so the last request always wins and an older, slower run can never overwrite
    /// a newer Live Activity or alert.
    private func synchronizeAmbientSessionSoon() {
        let previous = ambientSyncTask
        ambientSyncTask = Task {
            await previous?.value
            await synchronizeAmbientSession()
        }
    }

    private func synchronizeAmbientSession() async {
        let snapshot = sessionController.activeSession
        let skill = activeSkill
        let baseSeconds = activeBaseSeconds
        await liveActivityCoordinator.synchronize(
            snapshot: snapshot,
            skill: skill,
            baseTotalSeconds: baseSeconds,
            questAssignment: activeQuestAssignment
        )
        await notificationManager.synchronize(
            snapshot: snapshot,
            skill: skill,
            baseTotalSeconds: baseSeconds
        )
    }

    private func questLivePriority(_ assignment: QuestAssignment) -> Int {
        switch assignment.kind {
        case .some(.focusGoal): 0
        case .some(.deepSession): 1
        case .some(.activeTime): 2
        case .some(.journeymanXP): 3
        default: 10
        }
    }

    private func isLiveQuest(_ assignment: QuestAssignment) -> Bool {
        guard let kind = assignment.kind else { return false }
        return [
            QuestKind.focusGoal,
            .deepSession,
            .activeTime,
            .journeymanXP
        ].contains(kind)
    }

    private func seedBuiltInSkillsIfNeeded() throws {
        guard skills.isEmpty else { return }
        for (index, preset) in BuiltInSkills.presets.enumerated() {
            modelContext.insert(
                LifeSkill(
                    name: preset.name,
                    symbolName: preset.symbolName,
                    accentHex: preset.accentHex,
                    category: preset.category,
                    sortOrder: index
                )
            )
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

private struct LedgerFingerprint: Equatable {
    let skillID: UUID
    let totalActiveSeconds: Int
    let sessionCount: Int
}

private struct SkillFingerprint: Equatable {
    let id: UUID
    let name: String
    let symbolName: String
    let accentHex: String
    let curveVersion: Int
}

private struct QuestFingerprint: Equatable {
    let id: String
    let currentValue: Int
    let targetValue: Int
    let completedAt: Date?
    let retiredAt: Date?
}

private struct MiniSessionBar: View {
    let skill: LifeSkill
    let snapshot: ActiveSessionSnapshot
    let baseTotalSeconds: Int
    var usesOwnBackground = true
    let action: () -> Void

    var body: some View {
        let startingXP = ProgressionEngine.xp(
            forActiveSeconds: baseTotalSeconds,
            curveVersion: skill.progressionCurveVersion
        )

        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = snapshot.elapsedSeconds(at: context.date)
            let liveXP = ProgressionEngine.xp(
                forActiveSeconds: baseTotalSeconds + seconds,
                curveVersion: skill.progressionCurveVersion
            )

            Button(action: action) {
                HStack(spacing: 12) {
                    SkillGlyph(
                        symbolName: skill.symbolName,
                        color: Color(hex: skill.accentHex),
                        size: 40
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(snapshot.isAwaitingCommit
                            ? "Ready to review"
                            : snapshot.isPaused ? "Paused" : "Active session")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(DurationText.timer(seconds))
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text("+\(max(0, liveXP - startingXP).formatted()) XP")
                            .font(.caption)
                            .foregroundStyle(SkillingTimeTheme.gold)
                            .contentTransition(.numericText())
                    }

                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background {
                    if usesOwnBackground {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    if usesOwnBackground {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
                }
                .shadow(
                    color: usesOwnBackground ? .black.opacity(0.28) : .clear,
                    radius: 12,
                    y: 5
                )
            }
            .buttonStyle(SkillingTimePressStyle())
            .accessibilityLabel("Active \(skill.name) session")
            .accessibilityValue(
                "\(DurationText.compact(seconds)), \(snapshot.isPaused ? "paused" : "running")"
            )
            .accessibilityHint("Opens the active session")
        }
    }
}

@available(iOS 26.0, *)
private struct NativeSessionAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let skill: LifeSkill
    let snapshot: ActiveSessionSnapshot
    let baseTotalSeconds: Int
    let action: () -> Void

    var body: some View {
        if placement == .inline {
            compactAccessory
        } else {
            MiniSessionBar(
                skill: skill,
                snapshot: snapshot,
                baseTotalSeconds: baseTotalSeconds,
                usesOwnBackground: false,
                action: action
            )
        }
    }

    private var compactAccessory: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = snapshot.elapsedSeconds(at: context.date)
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: skill.symbolName)
                        .foregroundStyle(Color(hex: skill.accentHex))
                    Text(skill.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(snapshot.isAwaitingCommit
                        ? "Review"
                        : snapshot.isPaused ? "Paused" : DurationText.timer(seconds))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .contentTransition(.numericText())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SkillingTimePressStyle())
            .accessibilityLabel("Active \(skill.name) session")
            .accessibilityHint("Opens the active session")
        }
    }
}
