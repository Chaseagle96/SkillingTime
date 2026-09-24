import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pace

struct SkillPaceSection: View {
    let skill: LifeSkill
    let sessions: [SkillSession]

    var body: some View {
        let summary = SkillPace.summary(
            sessions: sessions,
            curveVersion: skill.progressionCurveVersion
        )
        let accent = Color(hex: skill.accentHex)

        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "Pace",
                subtitle: "Projections extend your last four weeks of real practice."
            )

            Chart(summary.weeks) { week in
                BarMark(
                    x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Minutes", Double(week.seconds) / 60)
                )
                .foregroundStyle(accent.gradient)
                .cornerRadius(4)
            }
            .chartYAxisLabel("Minutes")
            .frame(height: 150)
            .accessibilityLabel("Minutes practiced per week, last eight weeks")

            MetricCard(
                title: "Weekly average, last 4 weeks",
                value: DurationText.compact(summary.averageSecondsPerWeek),
                systemImage: "speedometer"
            )

            if let nextLevel = summary.nextLevel {
                estimateRow(nextLevel, systemImage: "arrow.up.circle.fill", accent: accent)
            }
            if let nextRank = summary.nextRank {
                estimateRow(nextRank, systemImage: "rosette", accent: accent)
            }
        }
    }

    private func estimateRow(
        _ estimate: PracticeMilestoneEstimate,
        systemImage: String,
        accent: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(estimate.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(DurationText.compact(estimate.secondsNeeded)) of practice to go")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = estimate.estimatedDate {
                    Text("At this pace, around \(Self.format(date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Practice this Skill to see a projection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private static func format(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear
            ? date.formatted(.dateTime.month(.wide).day())
            : date.formatted(.dateTime.month(.wide).day().year())
    }
}

// MARK: - Practice reminder

struct PracticeReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let skill: LifeSkill

    @State private var interval: PracticeReminderInterval = .off
    @State private var permissionDenied = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Remind me", selection: $interval) {
                        ForEach(PracticeReminderInterval.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("If I haven't practiced \(skill.name)")
                } footer: {
                    Text("One gentle note at 6 PM, repeating on the same schedule until you practice again. It is not a streak, and missing it costs nothing.")
                }

                if permissionDenied {
                    Section {
                        Label(
                            "Notifications are off for Skilling Time. Turn them on in Settings to get reminders.",
                            systemImage: "bell.slash.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Practice Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
            .task {
                interval = PracticeReminderScheduler.interval(for: skill.id)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        isSaving = true
        Task {
            if interval != .off {
                let allowed = await PracticeReminderScheduler.requestAuthorizationIfNeeded()
                guard allowed else {
                    permissionDenied = true
                    isSaving = false
                    return
                }
            }
            PracticeReminderScheduler.setInterval(interval, for: skill.id)
            await PracticeReminderScheduler.reschedule(in: modelContext)
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Backup

struct BackupSettingsSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var exportDocument: BackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingRestore: SkillingTimeBackup?
    @State private var resultMessage: String?

    private var exportFilename: String {
        "Skilling Time Backup \(Date.now.formatted(.iso8601.year().month().day()))"
    }

    var body: some View {
        Section {
            Button {
                prepareExport()
            } label: {
                Label("Export Backup", systemImage: "square.and.arrow.up")
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result {
                    resultMessage = "The backup was not saved. \(error.localizedDescription)"
                }
            }

            Button {
                showingImporter = true
            } label: {
                Label("Restore from Backup", systemImage: "square.and.arrow.down")
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                readBackup(result)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("A backup is one file with every session, Skill, and reward. Save it to Files or iCloud Drive. Restoring only adds what is missing, and never overwrites anything here.")
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore") { restorePending() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            if let backup = pendingRestore {
                Text("\(backup.sessions.count) sessions across \(backup.skills.count) Skills, exported \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
        .alert(
            "Backup",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func prepareExport() {
        do {
            let backup = try BackupService.makeBackup(in: modelContext)
            exportDocument = BackupDocument(data: try BackupService.encode(backup))
            showingExporter = true
        } catch {
            resultMessage = "The backup could not be created. \(error.localizedDescription)"
        }
    }

    private func readBackup(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            resultMessage = error.localizedDescription
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            do {
                pendingRestore = try BackupService.decode(try Data(contentsOf: url))
            } catch {
                resultMessage = error.localizedDescription
            }
        }
    }

    private func restorePending() {
        guard let backup = pendingRestore else { return }
        pendingRestore = nil
        do {
            let summary = try BackupService.restore(backup, into: modelContext)
            WidgetSnapshotPublisher.publish(in: modelContext)
            resultMessage = summary.message
        } catch {
            resultMessage = "Nothing was restored. \(error.localizedDescription)"
        }
    }
}
