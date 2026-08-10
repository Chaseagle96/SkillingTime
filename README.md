# Skilling Time 0.4: The Questboard

Skilling Time is a native, local-first iOS app that turns real activity into persistent RPG-style Skills. Version 0.4 gives each day a playable shape with a Today screen, adaptive Quests, forgiving Momentum, durable quest completion, personal records, and live Quest progress on the Lock Screen and Dynamic Island.

## What is new in 0.4

- **Today** is the new opening tab. It combines today's Skilling Time and earned XP, current Focus, Questboard, Momentum, active-session resume, and lifetime personal bests.
- The Questboard deterministically assigns three daily and two weekly Quests from the player's active Skills and recent history. An assignment remains frozen for its calendar period, so reopening the app cannot reroll it.
- Quest eligibility respects the real Skillbook. Diversify requires enough active Skills, Old Friend requires seven days away, Focus Goal requires an Apprentice Skill, and Journeyman's Work requires a Level 50 Skill.
- Targets adapt within bounded ranges from the prior 28 days. New players still receive achievable defaults.
- Quest progress is derived from authoritative `SkillSession` history. Completion is persisted as a dated event and remains earned if history is corrected later.
- **Momentum** shows active days across the last seven days and time invested this week without a punitive streak reset.
- Session completion now reveals every Quest completed by the session and any new personal record alongside level, Chronicle, Achievement, and capability rewards.
- Personal records recognize a Skill's longest session, most Skilling Time in one day, highest-XP day, and best week. Record events are append-only; current best values remain rebuildable from history.
- Live Activities show the most relevant active Quest and update time-based Quest progress directly on the Lock Screen and Dynamic Island. A completed target changes to **Quest Complete** while the session remains active.
- `ActivityDayLedger` provides rebuildable day-level aggregates for Today and Momentum. Exact XP-per-day is computed chronologically from each Skill's cumulative progression curve rather than approximated from duration.
- SwiftData schema v4 adds Quest assignments, day ledgers, personal-record events, and optional Focus Goal evidence on sessions.
- Released v1, v2, and v3 schemas now retain immutable model declarations. The migration test opens a real v3 on-disk store as v4 and verifies that the authoritative Skill and Session survive intact.

The deterministic progression economy is unchanged: completed time is authoritative, XP is derived at 20 XP per active minute under curve v1, Quests do not mint bonus XP, and Levels 1 through 100 plus unlimited Mastery stars keep their published thresholds.

## Data boundaries

`SkillSession` remains the source of truth. Quest and Today data are either durable outcomes or disposable caches:

```text
timer or manual entry
    -> SessionCommitService
    -> validate and write SkillSession
    -> resolve progression and permanent rewards
    -> reconcile SkillLedger and ActivityDayLedger
    -> resolve Quest completion and personal records
    -> save once
    -> SessionOutcome ceremony
```

- `QuestAssignment` freezes a generated challenge and permanently records completion. Its `currentValue` can be rebuilt from sessions.
- `ActivityDayLedger` and `SkillLedger` are acceleration data. Both can be recreated from session history.
- `PersonalRecordEvent`, `AchievementUnlock`, and `ChronicleUnlock` are append-only historical evidence.
- Corrections and deletions recompute ledger and Quest progress in the same transaction while preserving rewards already earned.
- The App Group still contains only the recoverable active timer and progression-alert preference. Completed history never moves into the Widget extension.

## Requirements

- Xcode 26.2 or newer
- iOS 17.0 or newer
- A physical iPhone for final Live Activity, Dynamic Island, notification, migration, and sideload validation
- No third-party runtime dependencies

iOS 26 uses the native Liquid Glass-compatible tab-bar bottom accessory. iOS 17 through 25 retain the existing overlay.

## Run and migrate

1. Back up an existing app container before the first physical migration test.
2. Open `SkillingTime.xcodeproj` in Xcode 26.2 or newer.
3. Select the shared **SkillingTime** scheme.
4. In **Signing & Capabilities**, choose the same Apple Developer team for `SkillingTime` and `SkillingTimeWidgets`.
5. Register or replace App Group `group.com.projectskillbook.app` for both targets if the bundle identifiers are customized.
6. Run `SkillingTimeTests`, then install on a physical iPhone over the existing v0.3.1 build.

On first launch, SwiftData migrates the existing store to schema v4, preserves all completed history and reward records, rebuilds missing day ledgers, and generates the current Questboard. No migration changes an existing Skill's progression curve version or XP thresholds.

## Signing and SideStore gate

The WidgetKit extension is entitlement-sensitive. A sideloaded build needs provisioning for:

- `com.projectskillbook.app`
- `com.projectskillbook.app.SkillingTimeWidgets`
- `group.com.projectskillbook.app`

Validate the complete archive on the actual SideStore setup before distribution. Confirm that the extension is embedded, both targets share the App Group entitlement, pause/resume survives a locked-screen round trip, Finish opens the correction sheet, Quest progress appears in the Live Activity, and an upgrade preserves a copy of real v0.3.1 history.

## Tests

The suite covers:

- frozen v1 XP thresholds, milestones, multi-level crossings, and Mastery
- finish-time freezing, idempotent commits, restoration, correction, and deletion
- Focus Goals, lifetime retired-Skill semantics, and append-only rewards
- deterministic Quest generation, eligibility gates, period freezing, and permanent completion
- exact day time and XP aggregation
- personal-record detection
- an on-disk v3-to-v4 SwiftData migration that preserves Skill and Session identity and values
- exact next-level notification planning and shared-store pause/resume behavior

## Intentionally deferred

Version 0.4 does not add Attributes, stat allocation, quest currencies, shops, social accounts, leaderboards, multiplayer, monetization, AI coaching, or an Apple Watch app. It deepens the daily loop while keeping time-based progression authoritative.
