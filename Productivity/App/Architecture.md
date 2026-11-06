# FocusGrove Architecture

## Direction

FocusGrove is structured as a background-first macOS app with a timeline UI on top. The core product loop is:

1. Track active applications and context changes.
2. Normalize those events into activity segments.
3. Classify each segment as productive, neutral, or distracting.
4. Persist the day as timeline data.
5. Generate live, daily, and weekly insights from the same source of truth.

## Folders

- `App`: app entry, dependency container, lifecycle coordination.
- `Core/Models`: value types shared across tracking, storage, insights, and UI.
- `Core/Services/ActivityTracking`: background trackers that emit normalized activity segments.
- `Core/Services/Classification`: rule and model based productivity labeling.
- `Core/Services/Insights`: daily and weekly summary generation.
- `Core/Persistence`: storage boundary for timeline segments.
- `Features/Dashboard`: main app shell and dashboard state.
- `Features/Timeline`: video-editor inspired timeline lanes and stream rendering.
- `Features/Insights`: insight presentation components.
- `Features/Settings`: future permission, labeling, and automation controls.
- `Shared/UI`: design tokens and reusable view primitives.

## Near-Term Implementation Steps

1. Keep preview/test-only trackers and sample activity behind debug-only compilation.
2. Add window-title capture only after explicit Accessibility permission handling.
3. Add retention and optional encrypted backup policies for `SQLiteBackedActivityRepository`.
4. Add a labeling UI so users can override default rules per app, site, or activity title.
5. Optimize `TimelineEditorView` with `Canvas` when rendering long daily or weekly histories.

## Local Activity Storage

The activity timeline uses `SQLiteBackedActivityRepository` as the local source of truth. The store is optimized for time-series data:

- A single SQLite database lives under Application Support and stores activity segments plus timeline label edits.
- Segments are upserted by stable `UUID`, allowing live tracker snapshots to extend an in-progress segment without creating duplicates.
- Date-range queries use indexed interval overlap checks, which protects retrieval for long local history without scanning the whole store.
- SQLite WAL mode handles durable incremental writes without the app maintaining custom daily bucket compaction.
- On first launch after the migration, the repository imports legacy daily binary files and marks the migration complete in database metadata.

## App Store Privacy Configuration

- The app target enables the macOS App Sandbox. The built app is signed with sandbox and user-selected read-only file access entitlements.
- `PrivacyInfo.xcprivacy` declares app-only `UserDefaults` use with required reason `CA92.1`.
- Activity data is stored locally in the app container or user-selected export/import locations. The app does not declare tracking domains or collected data in the privacy manifest because it does not upload local activity history.
- Visible companion window detection only reads window metadata after macOS reports Screen Recording access is already available. The app does not request Screen Recording access; without it, this companion signal degrades while foreground app tracking, idle handling, background audio detection, manual events, Pomodoro, persistence, exports, and insights continue.

### Persistence Algorithm

```text
startup:
    open ActivityStore.sqlite
    enable SQLite WAL mode
    create metadata, activity, and timeline-label tables if needed
    if legacy migration metadata is absent:
        import legacy daily binary activity and timeline-label files
        mark migration complete

on tracker snapshot(segments):
    begin transaction
    for segment in segments where segment.end > segment.start:
        upsert by UUID
        keep the existing row when the incoming snapshot has an older end date
    commit

timeline label replacement(interval, labels):
    read labels overlapping interval
    preserve portions outside interval
    normalize replacement labels
    delete rows overlapping interval
    insert preserved + replacement rows in one transaction

insight retrieval(interval):
    SELECT ordered rows WHERE start < interval.end AND end > interval.start
```
