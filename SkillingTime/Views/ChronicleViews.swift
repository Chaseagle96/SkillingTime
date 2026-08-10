import SwiftData
import SwiftUI

struct ChronicleRootView: View {
    @Query(sort: \LifeSkill.sortOrder) private var skills: [LifeSkill]
    @Query private var sessions: [SkillSession]
    @Query private var ledgers: [SkillLedger]
    @Query(sort: \AchievementUnlock.unlockedAt) private var achievementUnlocks: [AchievementUnlock]
    @Query(sort: \ChronicleUnlock.unlockedAt) private var chronicleUnlocks: [ChronicleUnlock]
    @State private var selection = 0

    var body: some View {
        let index = SessionAnalytics.index(ledgers: ledgers)

        VStack(spacing: 0) {
            Picker("Chronicle section", selection: $selection) {
                Text("Chronicle").tag(0)
                Text("Achievements").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if selection == 0 {
                ChronicleListView(
                    skills: skills,
                    index: index,
                    unlocks: chronicleUnlocks
                )
            } else {
                AchievementGalleryView(
                    skills: skills,
                    sessions: sessions,
                    unlocks: achievementUnlocks
                )
            }
        }
        .navigationTitle("Chronicle")
        .skillingTimeScreenBackground()
    }
}

private struct ChronicleListView: View {
    let skills: [LifeSkill]
    let index: SessionIndex
    let unlocks: [ChronicleUnlock]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ParchmentCard {
                    VStack(spacing: 8) {
                        Image(systemName: "scroll.fill")
                            .font(.title)
                        Text("THE CHRONICLE")
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .tracking(1.4)
                        Text("Every earned chapter is dated and kept with your lifetime Skillbook.")
                            .font(.system(.subheadline, design: .serif))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }

                if skills.isEmpty {
                    EmptyStateCard(
                        systemImage: "scroll",
                        title: "No Skills yet",
                        message: "Create a Skill to begin writing its Chronicle."
                    )
                } else {
                    ForEach(skills) { skill in
                        let skillUnlocks = unlocks.filter { $0.skillID == skill.id }
                        NavigationLink {
                            SkillChronicleView(
                                skill: skill,
                                progress: SessionAnalytics.progress(for: skill, index: index),
                                unlocks: skillUnlocks
                            )
                        } label: {
                            ChronicleSkillRow(
                                skill: skill,
                                progress: SessionAnalytics.progress(for: skill, index: index),
                                unlockedChapterCount: skillUnlocks.count
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 110)
        }
    }
}

private struct ChronicleSkillRow: View {
    let skill: LifeSkill
    let progress: ProgressSnapshot
    let unlockedChapterCount: Int

    var body: some View {
        HStack(spacing: 14) {
            SkillGlyph(
                symbolName: skill.symbolName,
                color: Color(hex: skill.accentHex),
                size: 52,
                rank: progress.rank
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(skill.name)
                        .font(.headline)
                    if skill.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Level \(progress.level) · \(progress.displayRank)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(unlockedChapterCount)/\(ChronicleContent.entries.count)")
                    .font(.headline)
                Text("CHAPTERS")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this Skill's Chronicle")
    }
}

private struct SkillChronicleView: View {
    let skill: LifeSkill
    let progress: ProgressSnapshot
    let unlocks: [ChronicleUnlock]

    private var unlocksByMilestone: [Int: ChronicleUnlock] {
        Dictionary(uniqueKeysWithValues: unlocks.map { ($0.milestoneLevel, $0) })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    SkillGlyph(
                        symbolName: skill.symbolName,
                        color: Color(hex: skill.accentHex),
                        size: 66,
                        rank: progress.rank
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(skill.name)
                                .font(.title2.bold())
                            if skill.isArchived {
                                Image(systemName: "archivebox.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Level \(progress.level) · \(progress.displayRank)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(
                    Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )

                ForEach(ChronicleContent.entries) { entry in
                    ChronicleChapterCard(
                        skillName: skill.name,
                        entry: entry,
                        unlockedAt: unlocksByMilestone[entry.level]?.unlockedAt
                    )
                }
            }
            .padding(16)
        }
        .navigationTitle("Chronicle")
        .navigationBarTitleDisplayMode(.inline)
        .skillingTimeScreenBackground()
    }
}

private struct ChronicleChapterCard: View {
    let skillName: String
    let entry: ChronicleEntry
    let unlockedAt: Date?

    var body: some View {
        Group {
            if let unlockedAt {
                ParchmentCard {
                    VStack(spacing: 12) {
                        Text(entry.chapter)
                            .font(.system(.headline, design: .serif))
                        Text("\(entry.rank.rawValue) · Level \(entry.level)")
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                        Text("Earned \(unlockedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(SkillingTimeTheme.ink.opacity(0.65))
                        Divider().overlay(SkillingTimeTheme.ink.opacity(0.25))
                        Text(entry.passage)
                            .font(.system(.body, design: .serif))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                        Label(entry.unlockTitle, systemImage: "seal.fill")
                            .font(.subheadline.weight(.semibold))
                        Text(entry.unlockDescription)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    Text(entry.chapter)
                        .font(.headline)
                    Text("Reach Level \(entry.level) in \(skillName) to unlock this chapter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(
                    Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(0.07),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                        )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AchievementGalleryView: View {
    let skills: [LifeSkill]
    let sessions: [SkillSession]
    let unlocks: [AchievementUnlock]

    @State private var selectedSkillID: UUID?

    private var selectedSkill: LifeSkill? {
        guard let selectedSkillID else { return nil }
        return skills.first { $0.id == selectedSkillID }
    }

    private var statuses: [AchievementStatus] {
        if let selectedSkill {
            return AchievementEngine.statuses(for: selectedSkill, sessions: sessions)
        }
        return AchievementEngine.globalStatuses(skills: skills, sessions: sessions)
    }

    private var scopedUnlocks: [String: AchievementUnlock] {
        let matching = unlocks.filter { record in
            if let selectedSkillID {
                return record.skillID == selectedSkillID
            }
            return record.skillID == nil
        }
        return Dictionary(uniqueKeysWithValues: matching.map { ($0.id, $0) })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(scopedUnlocks.count) of \(statuses.count) earned")
                            .font(.title2.bold())
                        Text("\(unlocks.count) dated unlock records")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .font(.title)
                        .foregroundStyle(SkillingTimeTheme.gold)
                }
                .padding(16)
                .background(
                    Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )

                Picker("Achievement scope", selection: $selectedSkillID) {
                    Text("Global").tag(Optional<UUID>.none)
                    ForEach(skills) { skill in
                        Text(skill.isArchived ? "\(skill.name) (Retired)" : skill.name)
                            .tag(Optional(skill.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(statuses) { status in
                    AchievementRow(
                        status: status,
                        unlock: scopedUnlocks[status.id]
                    )
                }
            }
            .padding(16)
            .padding(.bottom, 110)
        }
    }
}

private struct AchievementRow: View {
    let status: AchievementStatus
    let unlock: AchievementUnlock?

    private var isEarned: Bool { unlock != nil }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill((isEarned ? SkillingTimeTheme.gold : Color.secondary).opacity(0.12))
                Image(systemName: isEarned ? status.definition.systemImage : "lock.fill")
                    .foregroundStyle(isEarned ? SkillingTimeTheme.gold : Color.gray)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(status.definition.title)
                        .font(.subheadline.weight(.semibold))
                    if isEarned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(SkillingTimeTheme.success)
                    }
                }
                Text(status.definition.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SkillProgressBar(
                    fraction: isEarned ? 1 : status.fractionComplete,
                    accent: isEarned ? SkillingTimeTheme.gold : Color.gray,
                    height: 5
                )
                if let unlock {
                    Text("Earned \(unlock.unlockedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(SkillingTimeTheme.success)
                } else {
                    Text(status.progressLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(13)
        .background(
            Color.white.opacity(isEarned ? 0.055 : 0.03),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
