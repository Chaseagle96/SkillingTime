import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct CharacterView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var notificationManager: ProgressionNotificationManager
    @Query(sort: \LifeSkill.sortOrder) private var allSkills: [LifeSkill]
    @Query private var ledgers: [SkillLedger]
    @Query private var specializations: [SkillSpecialization]
    @Query(sort: \AchievementUnlock.unlockedAt) private var achievementUnlocks: [AchievementUnlock]
    @Query(sort: \ChronicleUnlock.unlockedAt) private var chronicleUnlocks: [ChronicleUnlock]

    var body: some View {
        let index = SessionAnalytics.index(ledgers: ledgers)
        let totalLevel = SessionAnalytics.totalLevel(skills: allSkills, index: index)
        let rankedSkills = makeRankedSkills(index: index)
        let artifacts = makeArtifacts()

        ScrollView {
            VStack(spacing: 20) {
                characterSheet(totalLevel: totalLevel)
                overviewGrid(
                    index: index,
                    totalLevel: totalLevel,
                    artifactCount: artifacts.count
                )
                progressionAlertsCard
                artifactSection(artifacts: artifacts)
                strongestSkills(rankedSkills)
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .navigationTitle("Character")
        .skillingTimeScreenBackground()
        .task {
            await notificationManager.refreshAuthorizationStatus()
        }
    }

    private var progressionAlertsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: notificationManager.alertsEnabled
                    ? "bell.badge.fill"
                    : "bell.slash")
                    .font(.title3)
                    .foregroundStyle(
                        notificationManager.alertsEnabled
                            ? SkillingTimeTheme.gold
                            : Color.secondary
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Progression Alerts")
                        .font(.headline)
                    Text("Notify me when the active session reaches its next level or Mastery star.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if notificationManager.authorizationStatus == .denied {
                Button("Open Notification Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)
            } else if notificationManager.alertsEnabled {
                Button("Disable Alerts", role: .destructive) {
                    notificationManager.disableAlerts()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Enable Progression Alerts") {
                    Task {
                        await notificationManager.enableAlerts()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SkillingTimeTheme.gold)
            }

            if let message = notificationManager.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func characterSheet(totalLevel: Int) -> some View {
        ParchmentCard {
            VStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(SkillingTimeTheme.ink.opacity(0.07))
                    Circle()
                        .strokeBorder(SkillingTimeTheme.mutedGold, lineWidth: 2)
                    Image(systemName: "person.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(SkillingTimeTheme.ink.opacity(0.78))
                }
                .frame(width: 82, height: 82)

                VStack(spacing: 3) {
                    Text("THE PRACTITIONER")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                    Text("Lifetime Level \(totalLevel)")
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                    Text("A character sheet written through real time and effort.")
                        .font(.system(.subheadline, design: .serif))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
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
                title: "Sessions",
                value: index.sessionCount.formatted(),
                systemImage: "checkmark.seal"
            )
            MetricCard(
                title: "Active Skills",
                value: allSkills.filter { !$0.isArchived }.count.formatted(),
                systemImage: "square.grid.2x2"
            )
            MetricCard(
                title: "Achievements",
                value: achievementUnlocks.count.formatted(),
                systemImage: "trophy.fill"
            )
            MetricCard(
                title: "Artifacts",
                value: artifactCount.formatted(),
                systemImage: "seal.fill"
            )
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
