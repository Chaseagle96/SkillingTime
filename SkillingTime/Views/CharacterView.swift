import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct CharacterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LifeSkill.sortOrder) private var allSkills: [LifeSkill]
    @Query private var ledgers: [SkillLedger]
    @Query private var specializations: [SkillSpecialization]
    @Query(sort: \AchievementUnlock.unlockedAt) private var achievementUnlocks: [AchievementUnlock]
    @Query(sort: \ChronicleUnlock.unlockedAt) private var chronicleUnlocks: [ChronicleUnlock]
    @Query private var pathLedgers: [CharacterPathLedger]
    @Query private var characterProfiles: [CharacterProfile]
    @Query(sort: \CharacterTitleUnlock.unlockedAt, order: .reverse)
    private var titleUnlocks: [CharacterTitleUnlock]
    @Query private var pathAssignments: [SkillPathAssignment]
    @Query(sort: \ExpertChallenge.startedAt, order: .reverse)
    private var expertChallenges: [ExpertChallenge]
    @Query private var legacies: [SkillLegacy]

    @State private var showingSettings = false
    @State private var showingPathReview = false
    @State private var preparationError: String?

    private var profile: CharacterProfile? { characterProfiles.first }

    var body: some View {
        let index = SessionAnalytics.index(ledgers: ledgers)
        let totalLevel = SessionAnalytics.totalLevel(skills: allSkills, index: index)
        let rankedSkills = makeRankedSkills(index: index)
        let artifacts = makeArtifacts()

        ScrollView {
            VStack(spacing: 20) {
                characterSheet(totalLevel: totalLevel)
                    .skillingTimeReveal(order: 0)

                if profile?.pathReviewCompletedAt == nil {
                    pathReviewCard
                        .skillingTimeReveal(order: 1)
                }

                pathSection
                    .skillingTimeReveal(order: 2)
                overviewGrid(
                    index: index,
                    totalLevel: totalLevel,
                    artifactCount: artifacts.count
                )
                .skillingTimeReveal(order: 3)
                masterySection
                    .skillingTimeReveal(order: 4)
                titleSection
                    .skillingTimeReveal(order: 5)
                artifactSection(artifacts: artifacts)
                    .skillingTimeReveal(order: 6)
                strongestSkills(rankedSkills)
                    .skillingTimeReveal(order: 7)
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .navigationTitle("Character")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Character Settings", systemImage: "gearshape.fill")
                    }
                    Button {
                        showingPathReview = true
                    } label: {
                        Label("Review Skill Paths", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Character options")
            }
        }
        .sheet(isPresented: $showingSettings) {
            CharacterSettingsView()
        }
        .sheet(isPresented: $showingPathReview) {
            PathReviewView()
        }
        .alert(
            "Character Could Not Refresh",
            isPresented: Binding(
                get: { preparationError != nil },
                set: { if !$0 { preparationError = nil } }
            )
        ) {
            Button("OK") { preparationError = nil }
        } message: {
            Text(preparationError ?? "Character progression remains recoverable from session history.")
        }
        .task {
            do {
                try CharacterProgressionService.prepare(in: modelContext)
            } catch {
                preparationError = error.localizedDescription
            }
        }
        .skillingTimeScreenBackground()
    }

    private func characterSheet(totalLevel: Int) -> some View {
        let equippedTitle = profile?.equippedTitleID.flatMap { identifier in
            titleUnlocks.first { $0.id == identifier }
        }
        let signature = CharacterProgressionEngine.buildSignature(ledgers: pathLedgers)
        let accent = Color(hex: profile?.accentHex ?? "D2A84A")

        return ParchmentCard {
            VStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                    Circle()
                        .strokeBorder(SkillingTimeTheme.mutedGold, lineWidth: 2)
                    Image(systemName: profile?.crestSymbolName ?? "person.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(SkillingTimeTheme.ink.opacity(0.82))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 86, height: 86)

                VStack(spacing: 4) {
                    Text((equippedTitle?.title ?? signature).uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                    Text(profile?.displayName ?? "The Practitioner")
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("Lifetime Level \(totalLevel)")
                        .font(.headline)
                    Text("A character written through real time and effort.")
                        .font(.system(.subheadline, design: .serif))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private var pathReviewCard: some View {
        Button {
            showingPathReview = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(SkillingTimeTheme.gold)
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Confirm Your Character Paths")
                        .font(.headline)
                    Text("Review how existing Skills contribute to your character build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .background(
                SkillingTimeTheme.gold.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SkillingTimeTheme.gold.opacity(0.24))
            }
        }
        .buttonStyle(.plain)
    }

    private var pathSection: some View {
        VStack(spacing: 12) {
            SectionTitle(
                title: "Character Paths",
                subtitle: "Every level is derived from completed practice"
            )

            VStack(spacing: 10) {
                ForEach(
                    Array(CharacterPath.allCases.enumerated()),
                    id: \.element.id
                ) { index, path in
                    let ledger = pathLedgers.first { $0.pathRawValue == path.rawValue }
                    let progress = CharacterProgressionEngine.progress(
                        forActiveSeconds: ledger?.totalActiveSeconds ?? 0,
                        curveVersion: ledger?.curveVersion
                            ?? CharacterProgressionEngine.currentCurveVersion
                    )
                    CharacterPathRow(
                        path: path,
                        progress: progress,
                        totalSeconds: ledger?.totalActiveSeconds ?? 0,
                        skillNames: contributingSkillNames(for: path)
                    )
                    .skillingTimeReveal(order: index)
                }
            }
        }
    }

    private func overviewGrid(
        index: SessionIndex,
        totalLevel: Int,
        artifactCount: Int
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            MetricCard(
                title: "Lifetime Level",
                value: totalLevel.formatted(),
                systemImage: "chevron.up.2"
            )
            MetricCard(
                title: "Time Recorded",
                value: DurationText.compact(index.totalSeconds),
                systemImage: "hourglass"
            )
            MetricCard(
                title: "Achievements",
                value: achievementUnlocks.count.formatted(),
                systemImage: "trophy.fill"
            )
            MetricCard(
                title: "Character Titles",
                value: titleUnlocks.count.formatted(),
                systemImage: "signature"
            )
            MetricCard(
                title: "Expert Challenges",
                value: expertChallenges.filter(\.isComplete).count.formatted(),
                systemImage: "checkmark.seal.fill"
            )
            MetricCard(
                title: "Artifacts",
                value: artifactCount.formatted(),
                systemImage: "seal.fill"
            )
        }
    }

    @ViewBuilder
    private var masterySection: some View {
        let activeChallenges = expertChallenges.filter { $0.isActive() }
        if !activeChallenges.isEmpty || !legacies.isEmpty {
            VStack(spacing: 12) {
                SectionTitle(
                    title: "Mastery",
                    subtitle: "Expert undertakings and permanent Legacies"
                )

                ForEach(activeChallenges) { challenge in
                    let skill = allSkills.first { $0.id == challenge.skillID }
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label(challenge.title, systemImage: challenge.systemImage)
                                .font(.headline)
                            Spacer()
                            Text(skill?.name ?? "Skill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        SkillProgressBar(
                            fraction: challenge.fractionComplete,
                            accent: SkillingTimeTheme.gold,
                            height: 8
                        )
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
                        Color.white.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .accessibilityElement(children: .combine)
                }

                ForEach(legacies, id: \.skillID) { legacy in
                    let skill = allSkills.first { $0.id == legacy.skillID }
                    HStack(spacing: 12) {
                        Image(systemName: legacy.crestSymbolName)
                            .font(.title2)
                            .foregroundStyle(SkillingTimeTheme.gold)
                            .frame(width: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(legacy.masterTitle)
                                .font(.headline)
                            Text("Legacy of \(skill?.name ?? "Mastery")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
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

    private var titleSection: some View {
        VStack(spacing: 12) {
            SectionTitle(
                title: "Earned Titles",
                subtitle: "Equip any title from Character Settings"
            )

            if titleUnlocks.isEmpty {
                EmptyStateCard(
                    systemImage: "signature",
                    title: "Your first title awaits",
                    message: "Reach Level 25 on any Character Path to earn an equipable title."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(titleUnlocks.prefix(8).enumerated()), id: \.element.id) {
                        index, title in
                        HStack(spacing: 12) {
                            Image(systemName: title.systemImage)
                                .foregroundStyle(
                                    title.path.map { Color(hex: $0.accentHex) }
                                        ?? SkillingTimeTheme.gold
                                )
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(title.titleDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if profile?.equippedTitleID == title.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SkillingTimeTheme.success)
                                    .accessibilityLabel("Equipped")
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        .padding(.vertical, 10)
                        if index < min(titleUnlocks.count, 8) - 1 {
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

    private func artifactSection(artifacts: [CharacterArtifact]) -> some View {
        VStack(spacing: 12) {
            SectionTitle(
                title: "Artifacts",
                subtitle: "Major ranks earned across your lifetime Skillbook"
            )

            if artifacts.isEmpty {
                EmptyStateCard(
                    systemImage: "seal",
                    title: "The display case is empty",
                    message: "Your first Artifact is earned when any Skill reaches Level 25."
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 145), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(artifacts) { artifact in
                        ArtifactCard(
                            skill: artifact.skill,
                            entry: artifact.entry,
                            unlockedAt: artifact.record.unlockedAt
                        )
                    }
                }
            }
        }
    }

    private func strongestSkills(
        _ rankedSkills: [(skill: LifeSkill, progress: ProgressSnapshot, seconds: Int)]
    ) -> some View {
        VStack(spacing: 12) {
            SectionTitle(
                title: "Strongest Skills",
                subtitle: "Active and retired Skills ranked by lifetime XP"
            )
            VStack(spacing: 0) {
                ForEach(
                    Array(rankedSkills.prefix(8).enumerated()),
                    id: \.element.skill.id
                ) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        SkillGlyph(
                            symbolName: item.skill.symbolName,
                            color: Color(hex: item.skill.accentHex),
                            size: 40,
                            rank: item.progress.rank
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(item.skill.name)
                                    .font(.subheadline.weight(.semibold))
                                if item.skill.isArchived {
                                    Image(systemName: "archivebox.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(DurationText.compact(item.seconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let title = specializations.first(where: {
                                $0.skillID == item.skill.id
                            })?.title {
                                Text(title)
                                    .font(.caption2)
                                    .foregroundStyle(SkillingTimeTheme.gold)
                            }
                        }
                        Spacer()
                        Text("Level \(item.progress.level)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 10)
                    if index < min(rankedSkills.count, 8) - 1 {
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

    private func contributingSkillNames(for path: CharacterPath) -> String {
        let names = allSkills.filter { skill in
            CharacterProgressionEngine.currentPath(
                for: skill.id,
                assignments: pathAssignments
            ) == path
        }.map(\.name)
        if names.isEmpty { return "No Skills assigned" }
        let visible = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(visible) +\(names.count - 3)" : visible
    }

    private func makeRankedSkills(
        index: SessionIndex
    ) -> [(skill: LifeSkill, progress: ProgressSnapshot, seconds: Int)] {
        allSkills
            .map { skill in
                let seconds = index.statistics(for: skill.id).totalSeconds
                let progress = SessionAnalytics.progress(for: skill, index: index)
                return (skill, progress, seconds)
            }
            .sorted {
                if $0.progress.totalXP != $1.progress.totalXP {
                    return $0.progress.totalXP > $1.progress.totalXP
                }
                return $0.skill.name < $1.skill.name
            }
    }

    private func makeArtifacts() -> [CharacterArtifact] {
        let skillsByID = Dictionary(uniqueKeysWithValues: allSkills.map { ($0.id, $0) })
        return chronicleUnlocks.compactMap { record in
            guard
                let skill = skillsByID[record.skillID],
                let entry = ChronicleContent.entry(for: record.milestoneLevel)
            else { return nil }
            return CharacterArtifact(record: record, skill: skill, entry: entry)
        }
    }
}

private struct CharacterPathRow: View {
    let path: CharacterPath
    let progress: ProgressSnapshot
    let totalSeconds: Int
    let skillNames: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: path.systemImage)
                .font(.title2)
                .foregroundStyle(Color(hex: path.accentHex))
                .frame(width: 44, height: 44)
                .background(Color(hex: path.accentHex).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(path.title)
                        .font(.headline)
                    Spacer()
                    Text("Level \(progress.level)")
                        .font(.subheadline.weight(.semibold))
                }
                SkillProgressBar(
                    fraction: progress.fractionComplete,
                    accent: Color(hex: path.accentHex),
                    height: 8
                )
                HStack {
                    Text(skillNames)
                        .lineLimit(1)
                    Spacer()
                    Text(DurationText.compact(totalSeconds))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            "Level \(progress.level), \(DurationText.compact(totalSeconds)), \(skillNames)"
        )
    }
}

private struct CharacterSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var notificationManager: ProgressionNotificationManager
    @Query private var profiles: [CharacterProfile]
    @Query(sort: \CharacterTitleUnlock.unlockedAt) private var titles: [CharacterTitleUnlock]

    @State private var displayName = "The Practitioner"
    @State private var crestSymbolName = "person.fill"
    @State private var accentHex = "D2A84A"
    @State private var equippedTitleID = ""
    @State private var saveError: String?

    private let crests = [
        "person.fill", "shield.fill", "crown.fill", "seal.fill",
        "star.circle.fill", "sparkles", "flame.fill", "book.closed.fill"
    ]
    private let accents = ["D2A84A", "D97A43", "C85E5E", "8A72B5", "55A7A2", "A96AA2"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Character name", text: $displayName)
                        .textInputAutocapitalization(.words)
                    Picker("Equipped Title", selection: $equippedTitleID) {
                        Text("Build Signature").tag("")
                        ForEach(titles) { title in
                            Text(title.title).tag(title.id)
                        }
                    }
                }

                Section("Crest") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: 12
                    ) {
                        ForEach(crests, id: \.self) { symbol in
                            Button {
                                crestSymbolName = symbol
                                Haptics.selection()
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title2)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        crestSymbolName == symbol
                                            ? Color(hex: accentHex).opacity(0.18)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Accent") {
                    HStack {
                        ForEach(accents, id: \.self) { hex in
                            Button {
                                accentHex = hex
                                Haptics.selection()
                            } label: {
                                ZStack {
                                    Circle().fill(Color(hex: hex))
                                    if accentHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    progressionAlertsControl
                } header: {
                    Text("Progression Alerts")
                } footer: {
                    Text("Notify me when an active session reaches its next Skill level or Mastery star.")
                }

                if let saveError {
                    Section("Could Not Save") {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Character Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
            .task {
                await notificationManager.refreshAuthorizationStatus()
                if let profile = profiles.first {
                    displayName = profile.displayName
                    crestSymbolName = profile.crestSymbolName
                    accentHex = profile.accentHex
                    equippedTitleID = profile.equippedTitleID ?? ""
                }
            }
        }
    }

    @ViewBuilder
    private var progressionAlertsControl: some View {
        if notificationManager.authorizationStatus == .denied {
            Button("Open Notification Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        } else if notificationManager.alertsEnabled {
            Button("Disable Progression Alerts", role: .destructive) {
                notificationManager.disableAlerts()
            }
        } else {
            Button("Enable Progression Alerts") {
                Task { await notificationManager.enableAlerts() }
            }
        }
    }

    private func save() {
        do {
            let profile = try CharacterProgressionService.ensureProfile(in: modelContext)
            profile.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.crestSymbolName = crestSymbolName
            profile.accentHex = accentHex
            profile.equippedTitleID = equippedTitleID.isEmpty ? nil : equippedTitleID
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

private struct PathReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LifeSkill.sortOrder) private var skills: [LifeSkill]
    @Query(sort: \SkillPathAssignment.effectiveFrom) private var assignments: [SkillPathAssignment]
    @Query private var profiles: [CharacterProfile]

    @State private var selections: [UUID: CharacterPath] = [:]
    @State private var saveError: String?

    private var isInitialReview: Bool {
        profiles.first?.pathReviewCompletedAt == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(skills) { skill in
                        Picker(selection: binding(for: skill)) {
                            ForEach(CharacterPath.allCases) { path in
                                Label(path.title, systemImage: path.systemImage)
                                    .tag(path)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: skill.symbolName)
                                    .foregroundStyle(Color(hex: skill.accentHex))
                                    .frame(width: 28)
                                VStack(alignment: .leading) {
                                    Text(skill.name)
                                    if skill.isArchived {
                                        Text("Retired")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Skill Paths")
                } footer: {
                    Text(
                        isInitialReview
                            ? "This confirmed assignment applies to each Skill's existing history."
                            : "Changes take effect for future sessions. Earlier sessions retain their original Path."
                    )
                }

                Section {
                    Text("Paths describe completed practice. They never grant XP multipliers, bonuses, or spendable points.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let saveError {
                    Section("Could Not Save") {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isInitialReview ? "Confirm Paths" : "Review Paths")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .task { loadSelections() }
        }
    }

    private func binding(for skill: LifeSkill) -> Binding<CharacterPath> {
        Binding(
            get: {
                selections[skill.id]
                    ?? CharacterProgressionEngine.currentPath(
                        for: skill.id,
                        assignments: assignments
                    )
                    ?? CharacterProgressionEngine.suggestedPath(for: skill)
            },
            set: { selections[skill.id] = $0 }
        )
    }

    private func loadSelections() {
        for skill in skills {
            selections[skill.id] = CharacterProgressionEngine.currentPath(
                for: skill.id,
                assignments: assignments
            ) ?? CharacterProgressionEngine.suggestedPath(for: skill)
        }
    }

    private func save() {
        do {
            try CharacterProgressionService.confirmInitialPaths(
                selections: selections,
                in: modelContext
            )
            _ = try QuestBoardService.prepareCurrentBoard(in: modelContext)
            Haptics.selection()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct CharacterArtifact: Identifiable {
    let record: ChronicleUnlock
    let skill: LifeSkill
    let entry: ChronicleEntry

    var id: String { record.id }
}

private struct ArtifactCard: View {
    let skill: LifeSkill
    let entry: ChronicleEntry
    let unlockedAt: Date

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: skill.symbolName)
                .font(.title2)
                .foregroundStyle(Color(hex: skill.accentHex))
            Text(entry.rank.rawValue.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(SkillingTimeTheme.rankColor(entry.rank))
            Text(skill.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("Level \(entry.level)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(unlockedAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    SkillingTimeTheme.rankColor(entry.rank).opacity(0.3),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
    }
}
