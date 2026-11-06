# Productivity Test Inventory

Last verified: 2026-08-28

Current Xcode test plan: Productivity

Summary:
- Total tests: 158
- Enabled tests: 158
- Disabled tests: 0
- Latest full run: 158 passed, 0 failed
- Latest build: successful

## ProductivityTests

### ActivityLabelFromCategoryTests

- focus -> focus
- communication -> productive
- research -> productive
- entertainment -> unproductive
- system -> unproductive
- unknown -> unknown
- rollup duration includes specific productive labels
- rollup duration ignores invalid durations
- custom label definitions are saved and loaded

### ActivityRepositoryContractTests

- in-memory repository defaults to empty
- in-memory repository upserts live segment snapshots by ID
- file-backed repository replays unflushed WAL on startup
- file-backed repository stores multi-day segments in every overlapping day bucket
- file-backed repository removes empty day files after deleting their final segment
- file-backed repository tolerates duplicate IDs in a persisted day file
- file-backed repository quarantines corrupt day files and keeps loading healthy days
- file-backed repository full-day query does not load exclusive end day
- file-backed repository cleans old day buckets for unindexed upserts
- file-backed repository ignores shorter stale snapshots by ID

### ActivitySegmentPredicateTests

- manual.event.sleep.* bundleID -> isSleepEvent
- productivity.lifecycle.sleep bundleID -> isSleepEvent
- standard bundleID -> not isSleepEvent
- manual.event.* bundleID -> isManualEventContext
- standard bundleID -> not isManualEventContext
- productivity.lifecycle.* bundleID -> isLifecycleContext
- companion userDescription -> isCompanionContext
- nil userDescription -> not isCompanionContext
- negative-duration segment has no safeInterval
- zero-duration segment has no safeInterval
- short sleep event is not a day progress sleep boundary
- ten minute sleep event is a day progress sleep boundary
- non-sleep event is never a day progress sleep boundary

### AdvancedAnalyticsEngineHumanRollupTests

- analytics excludes sleep and lifecycle context from tracked totals
- overlapping apps are reduced to primary attention before ratio calculation
- custom productive labels stay visible in analytics breakdown

### BackupDecodingCompatibilityTests

- activity segment backups without labels derive labels from category
- older preference backups receive default optional fields

### CalendarBoardStorePersistenceTests

- calendar board store saves and reloads goals and normalized pins
- calendar board store clear persists empty board
- calendar board store heals corrupt persisted file

### DashboardViewModelPersistenceTests

- mock tracker defaults to empty
- live tracking persists only changed segment snapshots
- startup load feeds dashboard, insights, and analytics metric segments
- historical insight interval loads older local storage and label overlays
- editing today's labels preserves adjacent previous-day labels in UI state
- editing today's labels preserves previous-day portion of spanning label in UI state

### DurationFormattingTests

- zero seconds -> 0m
- negative interval clamps to 0m
- 59 seconds (sub-minute) -> 0m
- exactly 60 seconds -> 1m
- 90 seconds -> 1m (truncated, not rounded)
- exactly 1 hour -> 1h 0m
- 1 hour 30 minutes -> 1h 30m
- 23 hours 59 minutes -> 23h 59m

### ForegroundTrackingEligibilityTests

- regular Dock applications are eligible for primary tracking
- accessory and prohibited applications are ignored as primary foreground apps
- the Productivity app remains eligible when reviewing its own dashboard

### InsightEngineSummaryTests

- always returns exactly 3 summaries
- productive summary has correct formatted duration
- productive summary trend shows correct integer percentage
- zero tracked time: productive trend shows 0%
- summary categories are focus, entertainment, unknown in order

### ManualActivityEventHumanScheduleTests

- weekday recurrence creates only Monday through Friday segments
- custom weekly recurrence honors selected weekdays
- daily overnight event contributes both carried and same-day sleep
- upcoming alerts skip past occurrences and apply alert offset

### ManualActivityEventSleepFlowTests

- sleep event emits sleep segment
- cross-midnight sleep event contributes to next day progress
- manual form normalization preserves overnight sleep
- sleep time picker allows user-entered overnight end
- non-sleep time picker keeps same-day minimum duration

### PomodoroConfigurationRobustnessTests

- configuration initializer clamps invalid values to supported ranges
- decoded configuration is normalized before use
- view model normalizes mutated configuration before persisting

### PrimaryAttentionEdgeCaseTests

- reverse-order input produces same total duration as sorted input
- zero-duration segments are silently filtered out
- lifecycle + companion + primary in same input: only primary appears in output
- equal-score overlap: earlier-started segment retains attention until it ends
- all excluded contexts (companion + lifecycle): output is empty

### PrimaryAttentionTests

- empty input -> empty output
- companion context segments are excluded
- lifecycle context segments are excluded
- single non-overlapping segment passes through
- non-overlapping segments: total duration preserved
- overlapping segments: higher productivity score dominates
- completely identical overlapping segments: total duration = single span
- output has no time gaps across a continuous input range
- output segments are always non-overlapping
- companion context does not appear in primary output even when co-present

### ProductivityRatioTests

- zero totalTrackedTime -> ratio is 0.0 (no divide-by-zero)
- 100% productive -> ratio is 1.0
- 50% productive -> ratio is 0.5
- 0 productive out of non-zero tracked -> ratio is 0

### RuleBasedActivityClassifierUserRuleTests

- enabled user rule overrides built-in app classification
- disabled user rule falls back to built-in classification
- app-name matching is case-insensitive for renamed apps
- this app stays focus even if a persisted rule says otherwise

### TimelineLabelRepositoryContractTests

- in-memory label replacement preserves boundary-adjacent labels
- in-memory label replacement preserves existing label portions outside the interval
- file-backed label repository splits cross-midnight labels and reloads them
- file-backed label replacement removes previous-day labels that overlap the replacement interval
- file-backed label repository quarantines corrupt day files and keeps loading healthy days
- file-backed label repository full-day query does not load exclusive end day
- file-backed label all-read returns canonical cross-midnight labels
- file-backed label repository normalizes overlapping persisted labels

### TimelineLabelResizeUXTests

- dragging leading edge left shrinks previous label immediately
- dragging trailing edge right shrinks next label immediately
- dragging trailing edge left expands next label immediately
- live resize output remains non-overlapping

### TimelineLabelStoredOverrideCompositionTests

- stored override does not replace unrelated derived labels with unknown
- unknown blanket stored label is preserved as a valid user edit
- commit stores only labels that differ from derived labels
- commit does not store label edits outside derived activity
- commit preserves stored overrides outside the visible edit window
- commit clamps stored overrides to the current day

### WeeklyInsightLabelCorrectionTests

- stored label starting before activity is clipped to derived activity
- stored labels without derived activity are ignored

### DerivedLabelEdgeCaseTests

- communication category -> productive label
- research category -> productive label
- system category -> unproductive label
- unknown category -> unknown label
- gap between two primary segments is filled with an unknown label
- adjacent derived segments with same label are merged into one
- adjacent different-category segments produce two separate derived labels

### DerivedLabelTests

- empty input -> empty output
- companion-only input -> empty output
- focus segment -> focus label
- custom productive segment keeps custom label
- entertainment segment -> unproductive label
- derived labels cover the full input span

### NormalizedLabelEdgeCaseTests

- reverse-order input produces same result as sorted input
- many adjacent same-label segments collapse into one
- gap between same-label segments preserves two separate output segments
- single-millisecond segment is kept (duration > 0)
- single valid segment preserves identity
- fully overlapping same-label duplicates: total output duration equals span
- overlapping mixed labels: no overlap in output and total duration equals span

### NormalizedLabelTests

- empty input -> empty output
- zero-duration segment is dropped
- negative-duration segment is dropped
- single valid segment passes through unchanged
- non-overlapping segments pass through in order
- adjacent same-label segments are merged into one
- adjacent different-label segments are NOT merged
- overlapping segments: later-started segment wins
- fully-contained segment: inner wins for its range, outer fills around it
- three overlapping segments: last wins where all overlap
- output segments are non-overlapping
- total duration never exceeds input span

### TimelineStreamTests

- empty input -> empty streams
- only primary (non-companion) segments -> stream 1 is primary attention lane
- non-overlapping companions fit in a single extra lane
- overlapping companions are packed into separate lanes
- stream numbers are contiguous starting from 1

### CompanionOverlapRemovalTests

- companion fully covered by same-bundleID primary: companion lane is absent
- companion partially overlaps same-bundleID primary: non-overlapping remainder kept
- companion with different bundleID from primary: not subtracted, full duration kept
- only lifecycle segments: one stream is produced
