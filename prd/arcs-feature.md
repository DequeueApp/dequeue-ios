# PRD: Arcs Feature

**Status**: Draft
**Author**: Claude (with Victor)
**Created**: 2026-01-20
**Last Updated**: 2026-01-20
**Issue**: TBD (Linear)

---

## Executive Summary

**Arcs** are a higher-level organizational container that groups related Stacks, similar to how Epics organize Stories in JIRA. Users typically have 2-3 active Arcs per week (max 5), providing strategic context for their operational work.

**Name rationale**: "Arc" is a single word (like "Stack", "Task"), abstract, non-whimsical, and suggests a narrative journey with beginning, middle, and end. Verb-friendly: "Start an Arc", "Complete the Arc".

**Key Decisions:**
- **Maximum limit**: 5 active Arcs at a time (enforced in UI and service)
- **Stack relationship**: A Stack can belong to at most one Arc (optional, one-to-many)
- **Features**: Title, description, color, reminders, attachments
- **Ordering**: Arcs are reorderable via drag-and-drop
- **Tab position**: New "Arcs" tab as first tab (position 0) in navigation
- **Parent type**: Extends existing ParentType enum for polymorphic attachments/reminders

---

## 1. Overview

### 1.1 Problem Statement

Users managing multiple projects or areas of life often have related Stacks that belong together conceptually:
- A conference preparation might span multiple Stacks (pitch deck, logistics, follow-ups)
- A product launch might include marketing, engineering, and customer support Stacks
- A personal goal might have planning, execution, and review Stacks

Currently, there's no way to:
- Group related Stacks under a higher-level objective
- See strategic progress across related work
- Limit work-in-progress at the strategic level
- Visualize the "big picture" of ongoing initiatives

### 1.2 Proposed Solution

Implement an **Arcs** feature that provides:

| Hierarchy Level | Entity | Example |
|-----------------|--------|---------|
| Strategic | **Arc** | "OEM Strategy for Conference" |
| Operational | Stack | "Prepare pitch deck" |
| Tactical | Task | "Add competitor analysis slide" |

Arcs will:
- Appear in a dedicated tab (first position)
- Display as large, visually distinct cards
- Show associated Stacks with progress indicators
- Support reminders and attachments
- Enforce a 5-arc active limit for focus

### 1.3 Goals

- Enable users to organize Stacks under strategic objectives
- Provide visual progress tracking across related work
- Enforce work-in-progress limits to maintain focus
- Support the same rich features as Stacks (reminders, attachments)
- Maintain offline-first behavior with eventual sync

### 1.4 Non-Goals

- Nested Arcs (Arcs containing Arcs)
- Mandatory Arc assignment for Stacks (always optional)
- Automatic Arc creation based on Stack patterns
- Arc templates or presets
- Sharing Arcs across users (single-user for v1)
- Time-based Arc scheduling (start/end dates in v1)

---

## 2. User Stories

### 2.1 Primary User Stories

1. **As a user**, I want to create an Arc to group related Stacks, so I can track strategic progress.
2. **As a user**, I want to assign existing Stacks to an Arc, so I can organize my work hierarchically.
3. **As a user**, I want to see all my Arcs in a dedicated tab, so I can view my strategic priorities.
4. **As a user**, I want to see which Stacks belong to each Arc, so I understand the scope.
5. **As a user**, I want to see progress (completed/total Stacks) on each Arc, so I know how much remains.
6. **As a user**, I want to be limited to 5 active Arcs, so I maintain focus on strategic priorities.
7. **As a user**, I want to add reminders to Arcs, so I can schedule strategic check-ins.
8. **As a user**, I want to add attachments to Arcs, so I can store relevant documents.
9. **As a user**, I want to mark an Arc as complete, so I can celebrate finishing strategic work.
10. **As a user**, I want to reorder my Arcs by priority, so the most important appears first.

### 2.2 Edge Cases

- User tries to create 6th active Arc → UI prevents with explanation
- User assigns Stack to Arc, then deletes Arc → Stack becomes unassigned (nullify)
- User deletes all Stacks in an Arc → Arc remains (can add new Stacks)
- User completes all Stacks in an Arc → Arc auto-suggests completion
- Arc created offline → syncs when online with proper event handling
- Stack already in one Arc assigned to another → moves to new Arc (replaces)

---

## 3. Technical Design

### 3.1 Data Model

#### 3.1.1 Arc Model (New SwiftData Entity)

```swift
@Model
final class Arc {
    @Attribute(.unique) var id: String
    var title: String
    var arcDescription: String?
    var statusRawValue: String          // active, completed, paused, archived
    var sortOrder: Int
    var colorHex: String?               // Visual accent color
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    // Sync fields (standard pattern)
    var userId: String?
    var deviceId: String?
    var syncStateRawValue: String
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int

    // Relationship to Stacks (one Arc has many Stacks)
    @Relationship(deleteRule: .nullify, inverse: \Stack.arc)
    var stacks: [Stack] = []

    // Computed properties
    var status: ArcStatus {
        get { ArcStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRawValue) ?? .pending }
        set { syncStateRawValue = newValue.rawValue }
    }

    var isActive: Bool {
        status == .active && !isDeleted
    }

    /// Count of non-deleted, active Stacks
    var activeStackCount: Int {
        stacks.filter { !$0.isDeleted && $0.status == .active }.count
    }

    /// Count of completed Stacks
    var completedStackCount: Int {
        stacks.filter { !$0.isDeleted && $0.status == .completed }.count
    }

    /// Total non-deleted Stacks
    var totalStackCount: Int {
        stacks.filter { !$0.isDeleted }.count
    }

    /// Progress as fraction (0.0 to 1.0)
    var progress: Double {
        guard totalStackCount > 0 else { return 0 }
        return Double(completedStackCount) / Double(totalStackCount)
    }

    init(
        id: String = CUID.generate(),
        title: String,
        arcDescription: String? = nil,
        status: ArcStatus = .active,
        sortOrder: Int = 0,
        colorHex: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        userId: String? = nil,
        deviceId: String? = nil,
        syncState: SyncState = .pending,
        lastSyncedAt: Date? = nil,
        serverId: String? = nil,
        revision: Int = 1
    ) {
        self.id = id
        self.title = title
        self.arcDescription = arcDescription
        self.statusRawValue = status.rawValue
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.userId = userId
        self.deviceId = deviceId
        self.syncStateRawValue = syncState.rawValue
        self.lastSyncedAt = lastSyncedAt
        self.serverId = serverId
        self.revision = revision
    }
}
```

#### 3.1.2 Stack Model Updates

Add to existing `Stack.swift`:

```swift
// Relationship to Arc (optional, a Stack belongs to at most one Arc)
var arc: Arc?
var arcId: String?  // For sync compatibility (stores arc.id when arc is assigned)
```

**Note**: `arcId` is kept in sync with the `arc` relationship. When `arc` is set, `arcId` is updated to `arc?.id`. This supports sync events that reference the arc by ID.

#### 3.1.3 Enum Updates

Add to `Enums.swift`:

```swift
/// Status of an Arc
enum ArcStatus: String, Codable, CaseIterable {
    case active     // Currently being worked on
    case completed  // All work finished
    case paused     // Temporarily on hold
    case archived   // Historical, no longer relevant
}
```

Update `ParentType`:

```swift
enum ParentType: String, Codable {
    case stack
    case task
    case arc    // NEW: Supports attachments and reminders on Arcs
}
```

Add to `EventType`:

```swift
// Arc lifecycle events
case arcCreated
case arcUpdated
case arcDeleted
case arcCompleted
case arcPaused
case arcResumed
case arcReordered

// Stack-Arc association events
case stackAssignedToArc
case stackRemovedFromArc
```

### 3.2 Event Types

| Event Type | Description | Payload |
|------------|-------------|---------|
| `arc.created` | New Arc created | Full Arc state |
| `arc.updated` | Arc title, description, or color changed | Full Arc state |
| `arc.deleted` | Arc soft-deleted | arcId, timestamp |
| `arc.completed` | Arc marked as completed | arcId, timestamp |
| `arc.paused` | Arc paused | arcId, timestamp |
| `arc.resumed` | Arc resumed from paused | arcId, timestamp |
| `arc.reordered` | Arc sortOrder changed | arcId, sortOrder |
| `stack.assignedToArc` | Stack associated with Arc | stackId, arcId |
| `stack.removedFromArc` | Stack disassociated from Arc | stackId, previousArcId |

### 3.3 Service Layer

#### 3.3.1 ArcService (New)

```swift
@MainActor
final class ArcService {
    private let modelContext: ModelContext
    private let userId: String
    private let deviceId: String
    private let syncManager: SyncManager?

    // MARK: - CRUD Operations

    /// Create a new Arc
    func createArc(
        title: String,
        description: String? = nil,
        colorHex: String? = nil
    ) throws -> Arc

    /// Update Arc properties
    func updateArc(
        _ arc: Arc,
        title: String? = nil,
        description: String? = nil,
        colorHex: String? = nil
    ) throws

    /// Soft-delete an Arc (nullifies Stack relationships)
    func deleteArc(_ arc: Arc) throws

    // MARK: - Status Operations

    /// Mark Arc as completed
    func markAsCompleted(_ arc: Arc, completeAllStacks: Bool = false) throws

    /// Pause an Arc
    func pause(_ arc: Arc) throws

    /// Resume a paused Arc
    func resume(_ arc: Arc) throws

    // MARK: - Stack Association

    /// Assign a Stack to this Arc (removes from previous Arc if any)
    func assignStack(_ stack: Stack, to arc: Arc) throws

    /// Remove a Stack from its Arc
    func removeStackFromArc(_ stack: Stack) throws

    // MARK: - Reordering

    /// Update sort orders for multiple Arcs
    func updateSortOrders(_ arcs: [(Arc, Int)]) throws

    // MARK: - Constraints

    /// Check if user can create a new active Arc (< 5 active)
    func canCreateNewArc() -> Bool

    /// Count of active (non-deleted, non-completed) Arcs
    func activeArcCount() -> Int
}
```

### 3.4 Offline-First Behavior

1. **Creating an Arc offline**:
   - Arc created locally with `syncState: .pending`
   - On sync: pushed to server, receives `serverId`
   - Emit `arc.created` event

2. **Assigning Stack to Arc offline**:
   - Relationship updated locally
   - `arcId` field updated on Stack
   - Emit `stack.assignedToArc` event with `syncState: .pending`
   - On sync: resolve any ID conflicts

3. **Conflict resolution**:
   - Arc properties: LWW on `updatedAt`
   - Stack-Arc relationship: LWW (last assignment wins)
   - Deleted Arcs: LWW (can be re-created if needed)
   - 5-Arc limit: Enforced locally; server validates on sync

---

## 4. UI/UX Design

### 4.1 Tab Navigation

Add Arcs as first tab (position 0) in `MainTabView.swift`:

```
[Arcs] [Stacks] [Activity] [Settings]
  ^
  New tab with icon: "rays" (SF Symbol)
```

The "rays" icon suggests:
- Emanating directions (strategic breadth)
- Focus point (central objective)
- Progress/momentum

### 4.2 ArcsView (Main Tab)

Large card-based layout optimized for strategic overview:

```
┌─────────────────────────────────────────┐
│ Arcs                              [+ ]  │
├─────────────────────────────────────────┤
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │▓▓▓▓ OEM Strategy                    │ │
│ │                                     │ │
│ │ Prepare for annual conference       │ │
│ │                                     │ │
│ │ [Pitch Deck] [Logistics] [+Add]     │ │
│ │                                     │ │
│ │ [████████░░░░] 66%                  │ │
│ │ 🔔 2    📎 3                        │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │▓▓▓▓ Product Launch                  │ │
│ │ ...                                 │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ + New Arc                           │ │
│ │ 3 of 5 active arcs                  │ │
│ └─────────────────────────────────────┘ │
│                                         │
└─────────────────────────────────────────┘
```

**Features**:
- Cards are ~180pt tall with generous spacing
- Color bar at top (4pt accent strip)
- Title prominently displayed
- Description (max 2 lines, truncated)
- Stack pills in horizontal scroll
- Progress bar showing completed/total Stacks
- Reminder and attachment counts
- Drag-to-reorder via `List.onMove` or long-press gesture
- "New Arc" card shows limit status, disabled at 5

### 4.3 ArcCardView Component

```swift
struct ArcCardView: View {
    let arc: Arc
    let onTap: () -> Void
    let onStackTap: (Stack) -> Void
    let onAddStackTap: () -> Void

    var body: some View {
        // See implementation in Phase 2
    }
}
```

**Design specifications**:
- Corner radius: 16pt
- Color bar: 4pt height at top
- Padding: 16pt internal
- Shadow: subtle elevation
- Stack pills: horizontal ScrollView with LazyHStack
- Progress bar: 8pt height, rounded caps
- Icon counts: SF Symbols with numeric labels

### 4.4 ArcEditorView (Detail/Edit)

Full-screen editor matching StackEditorView pattern:

```
┌─────────────────────────────────────────┐
│ [Cancel]    Edit Arc        [Complete]  │
├─────────────────────────────────────────┤
│                                         │
│ Title                                   │
│ ┌─────────────────────────────────────┐ │
│ │ OEM Strategy for Conference         │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Description                             │
│ ┌─────────────────────────────────────┐ │
│ │ Prepare materials and logistics     │ │
│ │ for the annual industry conference  │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Color                                   │
│ ● ● ● ● ● ● ● ●  [Custom]               │
│                                         │
├─────────────────────────────────────────┤
│ Stacks (4)                      [+ Add] │
│ ┌─────────────────────────────────────┐ │
│ │ ☐ Pitch Deck                      → │ │
│ │ ☑ Travel Logistics                → │ │
│ │ ☐ Follow-up Plan                  → │ │
│ │ ☐ Speaker Notes                   → │ │
│ └─────────────────────────────────────┘ │
│                                         │
├─────────────────────────────────────────┤
│ Reminders (2)                   [+ Add] │
│ (Reuse RemindersSectionView)            │
│                                         │
├─────────────────────────────────────────┤
│ Attachments (3)                 [+ Add] │
│ (Reuse AttachmentsSectionView)          │
│                                         │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ [Pause Arc]                         │ │
│ │ [Delete Arc]                        │ │
│ └─────────────────────────────────────┘ │
│                                         │
└─────────────────────────────────────────┘
```

**Sections**:
1. Title & Description (editable text fields)
2. Color Picker (preset colors + custom hex)
3. Stacks list (with completion status, tap to navigate, add button)
4. Reminders (reuse existing `RemindersSectionView`)
5. Attachments (reuse existing `AttachmentsSectionView`)
6. Actions (Pause, Delete with confirmations)

### 4.5 Stack-Arc Association

#### In ArcEditorView

"Add Stack" button opens `StackPickerSheet`:

```
┌─────────────────────────────────────────┐
│ [Cancel]    Add Stack          [Done]   │
├─────────────────────────────────────────┤
│ 🔍 Search stacks...                     │
├─────────────────────────────────────────┤
│ Unassigned Stacks                       │
│ ┌─────────────────────────────────────┐ │
│ │ ☐ Quarterly Report                  │ │
│ │ ☐ Team Sync Prep                    │ │
│ │ ☐ Client Proposal                   │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Assigned to Other Arcs                  │
│ ┌─────────────────────────────────────┐ │
│ │ ☐ Budget Review (in "Finance Arc")  │ │
│ │   ⚠️ Will move to this Arc          │ │
│ └─────────────────────────────────────┘ │
│                                         │
└─────────────────────────────────────────┘
```

#### In StackEditorView

Add "Arc" section to assign Stack to an Arc:

```
│ Arc                                     │
│ ┌─────────────────────────────────────┐ │
│ │ ▓ OEM Strategy              [× ]    │ │
│ └─────────────────────────────────────┘ │
│ or                                      │
│ ┌─────────────────────────────────────┐ │
│ │ [+ Assign to Arc]                   │ │
│ └─────────────────────────────────────┘ │
```

#### In StackRowView

Show small colored dot indicating Arc membership:

```
┌─────────────────────────────────────────┐
│ ▓ Quarterly Report                    ★ │
│   Draft executive summary               │
└─────────────────────────────────────────┘
```

The colored dot uses the Arc's `colorHex` for visual grouping.

### 4.6 Color Picker Component

Preset colors matching iOS system palette:

```swift
struct ArcColorPicker: View {
    @Binding var selectedColor: String?

    let presetColors: [String] = [
        "FF6B6B",  // Red
        "FF9F43",  // Orange
        "FECA57",  // Yellow
        "48DBFB",  // Cyan
        "5F9EA0",  // Teal
        "A29BFE",  // Purple
        "FD79A8",  // Pink
        "636E72",  // Gray
    ]
}
```

### 4.7 Progress Bar Component

Reusable progress indicator:

```swift
struct ProgressBar: View {
    let progress: Double  // 0.0 to 1.0
    let height: CGFloat = 8
    var tintColor: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(tintColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: height)
    }
}
```

### 4.8 Empty States

**No Arcs created**:
```
┌─────────────────────────────────────────┐
│                                         │
│            [rays icon]                  │
│                                         │
│         Start Your First Arc            │
│                                         │
│   Arcs help you group related Stacks    │
│   and track progress on bigger goals.   │
│                                         │
│          [Create Arc]                   │
│                                         │
└─────────────────────────────────────────┘
```

**Arc with no Stacks**:
```
│ Stacks (0)                      [+ Add] │
│ ┌─────────────────────────────────────┐ │
│ │     Add Stacks to track progress    │ │
│ │           [+ Add Stack]             │ │
│ └─────────────────────────────────────┘ │
```

### 4.9 Platform Considerations

**iOS/iPadOS**:
- Cards in vertical scroll
- Drag-to-reorder with haptic feedback
- Sheet presentation for editors
- Color picker as popover on iPad

**macOS**:
- Cards in grid layout (2-3 columns based on width)
- Drag-to-reorder with cursor feedback
- Inspector-style editor panel or sheet
- Color picker as popover

---

## 5. Backend Changes

### 5.1 New Database Table

```sql
CREATE TABLE arcs (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    sort_order INTEGER NOT NULL DEFAULT 0,
    color_hex TEXT,
    created_at BIGINT NOT NULL,  -- Unix milliseconds
    updated_at BIGINT NOT NULL,  -- Unix milliseconds
    deleted BOOLEAN NOT NULL DEFAULT FALSE,
    revision INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX idx_arcs_user_id ON arcs(user_id);
CREATE INDEX idx_arcs_user_status ON arcs(user_id, status) WHERE deleted = FALSE;
```

### 5.2 Stack Table Update

```sql
ALTER TABLE stacks ADD COLUMN arc_id TEXT REFERENCES arcs(id);
CREATE INDEX idx_stacks_arc_id ON stacks(arc_id) WHERE arc_id IS NOT NULL;
```

### 5.3 Event Handling

Add handling for new event types in Go sync service:

- `arc.created` → Insert into `arcs` table
- `arc.updated` → Update `arcs` row
- `arc.deleted` → Set `deleted = true`
- `arc.completed` → Update status to 'completed'
- `arc.paused` → Update status to 'paused'
- `arc.resumed` → Update status to 'active'
- `arc.reordered` → Update `sort_order`
- `stack.assignedToArc` → Update `stacks.arc_id`
- `stack.removedFromArc` → Set `stacks.arc_id = NULL`

### 5.4 Sync Considerations

- Arcs sync independently from Stacks
- `stack.assignedToArc` events reference Arc by ID
- If Arc doesn't exist on device during sync, fetch it first
- 5-Arc limit enforced on server during event processing

---

## 6. Open Questions

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| 1 | Arc limit behavior | Hard block vs soft warning | Hard block with clear messaging |
| 2 | Completing Arc with incomplete Stacks | Allow vs require completion | Allow with confirmation dialog |
| 3 | Arc archive vs delete | Separate actions vs single | Archive for completed, delete for abandoned |
| 4 | Stack grouping in Stacks tab | Show Arc badge vs separate sections | Badge indicator (keeps single list) |
| 5 | Default color | None vs random vs first preset | None (optional enhancement) |
| 6 | Paused Arc behavior | Hide from main view vs dim | Dim with "Paused" badge |

---

## 7. Decisions Made

| Question | Decision | Rationale |
|----------|----------|-----------|
| Entity name | "Arc" | Single word, narrative metaphor, verb-friendly |
| Maximum limit | 5 active Arcs | Forces prioritization, research-backed WIP limit |
| Stack relationship | One-to-many (Stack has optional Arc) | Simple, covers 95% of use cases |
| Tab position | First tab (position 0) | Strategic work should be most visible |
| Color support | Optional, user-chosen | Visual grouping without complexity |
| Parent type integration | Extend existing ParentType enum | Reuses Reminder/Attachment infrastructure |
| Ordering | Manual drag-to-reorder | User controls priority display |
| Progress calculation | Completed Stacks / Total Stacks | Simple, intuitive metric |

---

## 8. Success Metrics

- Users can create and manage up to 5 active Arcs
- Stacks can be assigned to and removed from Arcs
- Progress bar accurately reflects Stack completion status
- Reminders and attachments work correctly on Arcs
- Arcs sync correctly across devices
- Arc operations complete in < 100ms locally
- ArcsView loads in < 150ms with 5 Arcs, 20+ Stacks total
- No performance regression in Stacks tab

---

## 9. Implementation Phases

### Phase 1: Foundation (Data Model & Events)

**iOS (dequeue-ios-2):**
1. Create `Arc.swift` SwiftData model
2. Add `ArcStatus` enum to `Enums.swift`
3. Update `ParentType` to include `.arc`
4. Add `arc` and `arcId` to `Stack.swift`
5. Add arc event types to `EventType` enum
6. Add `ArcState` and event payloads to `EventService.swift`
7. Create `ArcService.swift` with CRUD operations
8. Update `ProjectorService.swift` to handle arc events
9. Write unit tests for ArcService

**Backend (stacks-sync):**
- Add `arcs` table (migration)
- Add `arc_id` column to `stacks` table
- Add event type handling for arc events

### Phase 2: Basic UI

**iOS:**
1. Create `ArcCardView.swift` component
2. Create `ArcsView.swift` (main tab view)
3. Create `ProgressBar.swift` component
4. Add Arcs tab to `MainTabView.swift` at position 0
5. Create `ArcEditorView.swift` (title, description, color only)
6. Implement drag-to-reorder
7. Implement 5-arc limit UI with messaging
8. Empty state design and implementation

### Phase 3: Stack Association

**iOS:**
1. Create `StackPickerSheet.swift` (multi-select)
2. Create `ArcPickerSheet.swift` (single-select)
3. Add Arc section to `StackEditorView`
4. Add Stacks section to `ArcEditorView`
5. Implement assignStack/removeStack in ArcService
6. Add association event emission
7. Show Arc indicator dot on `StackRowView`

### Phase 4: Attachments & Reminders

**iOS:**
1. Extract `RemindersSectionView` from StackEditorView
2. Add Reminders section to ArcEditorView
3. Add Attachments section to ArcEditorView
4. Update AttachmentService for `.arc` parent type
5. Update ReminderService for `.arc` parent type
6. Test notifications for Arc reminders
7. Test attachment upload/download for Arcs

### Phase 5: Polish

**iOS:**
1. Arc completion flow with Stack completion options
2. Pause/Resume functionality
3. Archive view for completed Arcs
4. macOS layout adaptations
5. Accessibility audit (VoiceOver, Dynamic Type)
6. Animation polish (transitions, feedback)
7. UI tests for critical flows
8. Performance testing and optimization

---

## 10. Dependencies

- SwiftData relationship support (iOS 17+)
- Existing event system infrastructure
- Existing Reminder and Attachment models with ParentType
- Backend sync service updates
- No new third-party dependencies required

---

## 11. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Tab reordering breaks user habits | Medium | Clear announcement, consider migration period |
| 5-Arc limit frustrates power users | Medium | Clear messaging, paused Arcs don't count |
| Complex Stack-Arc sync conflicts | High | LWW resolution, comprehensive sync tests |
| Performance with many Stacks per Arc | Medium | Lazy loading, batch operations |
| Existing app complexity increases | Medium | Arcs tab is optional to use |
| SwiftData relationship performance | Medium | Monitor, optimize queries if needed |

---

## 12. Critical Files to Modify

| File | Changes |
|------|---------|
| `Models/Arc.swift` | **NEW** - Arc model |
| `Models/Stack.swift` | Add `arc` relationship and `arcId` |
| `Models/Enums.swift` | Add `ArcStatus`, arc events, update `ParentType` |
| `Services/ArcService.swift` | **NEW** - Arc business logic |
| `Services/EventService.swift` | Add `ArcState`, arc payloads, recording |
| `Services/ProjectorService.swift` | Handle arc events from sync |
| `Views/App/MainTabView.swift` | Add Arcs tab at position 0 |
| `Views/Arc/ArcsView.swift` | **NEW** - Main tab view |
| `Views/Arc/ArcCardView.swift` | **NEW** - Card component |
| `Views/Arc/ArcEditorView.swift` | **NEW** - Detail/edit view |
| `Views/Arc/ArcPickerSheet.swift` | **NEW** - Arc selection |
| `Views/Arc/StackPickerSheet.swift` | **NEW** - Stack selection for Arc |
| `Views/Stack/StackEditorView.swift` | Add Arc section |
| `Views/Home/StackRowView.swift` | Add Arc indicator dot |
| `Views/Shared/ProgressBar.swift` | **NEW** - Reusable progress component |
| `Views/Shared/ArcColorPicker.swift` | **NEW** - Color selection component |

---

## Appendix A: Color Palette Reference

Recommended Arc colors (8 presets):

| Name | Hex | Usage |
|------|-----|-------|
| Coral | `#FF6B6B` | Urgent, attention-needed |
| Tangerine | `#FF9F43` | Creative, energetic |
| Sunshine | `#FECA57` | Optimistic, planning |
| Sky | `#48DBFB` | Communication, meetings |
| Teal | `#5F9EA0` | Growth, learning |
| Lavender | `#A29BFE` | Personal, wellness |
| Rose | `#FD79A8` | Relationships, social |
| Slate | `#636E72` | Administrative, routine |

---

## Appendix B: Example User Flows

### Flow 1: Creating an Arc

1. User taps Arcs tab
2. User taps "+" button (or "New Arc" card)
3. ArcEditorView appears in create mode
4. User enters title: "Q1 Product Launch"
5. User enters description: "Coordinate all launch activities"
6. User selects coral color
7. User taps "Create"
8. Arc appears in ArcsView, events emitted

### Flow 2: Assigning Stacks to Arc

1. User taps Arc card to open ArcEditorView
2. User taps "+ Add" in Stacks section
3. StackPickerSheet shows available Stacks
4. User selects "Marketing Plan" and "Engineering Tasks"
5. User taps "Done"
6. Stacks appear in Arc's list, progress updates
7. Events emitted: `stack.assignedToArc` × 2

### Flow 3: Completing an Arc

1. User opens Arc with 3 Stacks (2 completed, 1 active)
2. User taps "Complete" button
3. Confirmation dialog: "Complete Arc? 1 Stack still active."
4. Options: "Complete All & Arc" / "Complete Arc Only" / "Cancel"
5. User chooses "Complete All & Arc"
6. All Stacks marked complete, Arc status → completed
7. Events emitted, Arc moves to completed section

---

## Appendix C: Accessibility Considerations

- All Arc cards have accessibility labels: "Arc: [title], [progress]% complete, [n] stacks"
- Progress bars announce percentage to VoiceOver
- Color selection has text labels, not color-only
- Drag-to-reorder announces "Moved [title] to position [n]"
- Arc limit warning is announced when approaching limit
- All interactive elements meet minimum tap target (44pt)
- Supports Dynamic Type up to accessibility sizes
