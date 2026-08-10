# Skilling Time 0.5.1: The Awakening

Skilling Time is a native, local-first iOS app that turns real activity into persistent RPG-style Skills. Version 0.5.1 gives the complete experience a deliberate motion language while preserving the data-integrity and Character systems introduced in 0.5.

## What is new in 0.5.1

- A branded native launch screen now uses a dark system background and the Skilling Time hourglass crest instead of an empty launch configuration.
- The first SwiftUI frame precisely continues that launch composition, then reveals the app without delaying initialization. The first launch is ceremonial; later cold launches are brief.
- The app icon now carries the same hourglass, six Path colors, and gold-on-obsidian identity instead of the previous solid-color placeholder.
- `SkillingTimeMotion` centralizes spring, progress, reveal, press, and ceremonial timing so animation behavior remains consistent.
- Skills use tactile press feedback, staggered entry, and an iOS 18-or-newer zoom transition into their detail screen.
- Today, Skillbook, Chronicle, Character, and Skill detail surfaces reveal according to visual hierarchy rather than appearing all at once.
- XP, timers, metrics, Quest progress, Character Paths, and Expert Challenges animate between meaningful values.
- Session entry now establishes the active Skill visually, and session rewards reveal in gameplay order.
- Quest completion, session start, reward, selection, and milestone moments use restrained contextual haptics.
- Reduce Motion removes spatial movement, long launch timing, card scaling, and stagger delays while preserving immediate state changes.
- Motion policies are deterministic and unit tested. No animation changes progression, persistence, or session timing.

## Character foundation from 0.5

- Six stable Character Paths describe practice without pretending to measure innate ability: **Vigor**, **Insight**, **Craft**, **Expression**, **Care**, and **Stewardship**.
- Every Skill has one effective-dated Path assignment. The first explicit review can classify existing history; later changes apply only to future sessions by default.
- Path XP, Levels, ranks, and progress are derived from completed active seconds through a separately versioned deterministic engine. Paths never add XP multipliers, bonuses, or spendable points.
- `CharacterPathLedger` provides rebuildable, constant-time Character reads while `SkillSession` remains authoritative.
- The Character tab now presents a crest, display name, equipped earned title, current build signature, Path progression, Mastery, Artifacts, and strongest Skills.
- Path milestones at Levels 25, 50, 75, and 100 permanently unlock equipable Character titles.
- The session-completion ceremony reveals Path time, Path level increases, Character titles, and completed Expert Challenges alongside existing rewards.
- One weekly Questboard slot is reserved for a Path-aware challenge such as **Deepen Insight**. It is based on real Skill assignments and still grants no synthetic XP.
- Level 75 now unlocks a functional **Expert Challenge**. Players choose a 30-day time, session-count, or Focus Goal undertaking. Completion grants a permanent title.
- Level 100 now unlocks **Legacy**, including a custom Master title and crest that can be equipped on the Character sheet.
- Expert Challenges appear on Today, the relevant Skill, and the Character sheet.
- Progression-alert controls moved into Character Settings so the main Character screen remains focused on identity.
- SwiftData schema v5 freezes the shipped v4 declarations, adds the Character models, and migrates v4 stores through an explicit lightweight stage.

The Skill progression economy remains unchanged: 20 XP per active minute under curve v1, Levels 1 through 100, unlimited Mastery stars, no Quest XP, and no Character-stat bonuses.

## Data boundaries

Completed sessions remain the source of truth:

```text
timer or manual entry
    -> SessionCommitService
    -> write SkillSession
    -> resolve Skill rewards and Quests
    -> resolve Character Path and Expert Challenge outcomes
    -> rebuild affected caches
    -> save once
    -> SessionOutcome ceremony
```

- `SkillPathAssignment` is effective-dated evidence for how sessions map to Character Paths.
- `CharacterPathLedger`, `SkillLedger`, and `ActivityDayLedger` are disposable acceleration data.
- `CharacterTitleUnlock`, `AchievementUnlock`, `ChronicleUnlock`, and completed Expert Challenges are permanent historical rewards.
- Session corrections and deletion recompute current Skill, Path, Quest, Challenge, and ledger values without erasing rewards already earned.
- Archived Skills remain part of Lifetime Level and Character Path history.
- The Widget extension still receives only recoverable active-session state. Character history never moves into the App Group.

## Requirements

- Xcode 26.2 or newer
- iOS 17.0 or newer
- A physical iPhone for final Live Activity, Dynamic Island, notification, migration, and sideload validation
- No third-party runtime dependencies

iOS 26 uses the native Liquid Glass-compatible tab-bar bottom accessory. iOS 17 through 25 retain the overlay fallback.

## Run and migrate

1. Back up an existing app container before the first physical migration test.
2. Open `SkillingTime.xcodeproj` in Xcode 26.2 or newer.
3. Select the shared **SkillingTime** scheme.
4. Choose the same Apple Developer team for `SkillingTime` and `SkillingTimeWidgets`.
5. Keep or replace App Group `group.com.projectskillbook.app` for both targets if bundle identifiers are customized.
6. Run `SkillingTimeTests`, then install over the existing v0.4 build.

On first launch, SwiftData migrates the store to schema v5. Character preparation suggests an initial Path for every existing Skill, rebuilds Path ledgers from authoritative sessions, and presents a review entry point. Confirming that first review explicitly applies the selected classifications to prior history. Subsequent Path changes are effective-dated for future sessions.

## Signing and SideStore gate

The Live Activity extension requires provisioning for:

- `com.projectskillbook.app`
- `com.projectskillbook.app.SkillingTimeWidgets`
- `group.com.projectskillbook.app`

Validate the complete archive on the actual SideStore setup before distribution. Confirm that both targets share the App Group, the WidgetKit extension is embedded, the active timer survives lock-screen actions, Path review preserves existing history, and a v0.4 store migrates without losing Skills or sessions.

## Tests

The suite covers:

- frozen Skill XP thresholds, milestones, Mastery, and curve-version routing
- session chronology, idempotent commits, restoration, correction, and deletion
- deterministic Quest generation, fixed periods, Path-aware weekly assignments, and permanent completion
- effective-dated Path attribution and rebuildable Path ledgers
- permanent Character titles after history correction
- Expert Challenge completion and title resolution
- v3-to-v5 and on-disk v4-to-v5 migration with authoritative history preservation
- Focus Goals, achievements, Chronicle rewards, personal records, notifications, and shared active-session storage
- first-launch, returning-launch, Reduce Motion, and bounded stagger timing policies

## Intentionally deferred

Version 0.5.1 does not add allocatable stats, XP multipliers, perks, currencies, equipment, inventory, shops, combat, random loot, social accounts, leaderboards, multiplayer, AI classification, monetization, or an Apple Watch app. Character progression describes completed behavior without inflating it.
