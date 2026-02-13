# PRD: Tags for Stacks

**Status**: ✅ FULLY IMPLEMENTED
**Author**: Claude (with Victor)
**Created**: 2026-01-03
**Last Updated**: 2026-02-13 (implementation complete)
**Implementation**: January 13-February 10, 2026
**Tickets**: DEQ-151, DEQ-153, DEQ-164, DEQ-171, DEQ-175, DEQ-31 + bug fixes

---

## ✅ Implementation Summary

**All core components implemented:**
- ✅ **Tag Model** (DEQ-151, PR #95) - SwiftData model with relationships
- ✅ **TagService** (PR #239) - Full CRUD with comprehensive tests
- ✅ **String Migration** (DEQ-153, PR #106) - Migrated from string tags to Tag objects
- ✅ **Tag Filter Bar** (DEQ-164, PR #112) - Home view filtering
- ✅ **Keyboard Navigation** (DEQ-171, PR #115) - Keyboard support for tag ops
- ✅ **Tag Sync Events** (DEQ-175, PR #117) - Event sourcing integration
- ✅ **Tasks Tagging** (DEQ-31, PR #258) - Tags on QueueTask
- ✅ **Cross-Device Sync** - Duplicate tag handling (DEQ-235, PR #221)
- ✅ **Tag Events in Log** (DEQ-198, PR #213) - Event history display
- ✅ **ProjectorService** - Full tag event processing

**Status:** Feature complete as of February 10, 2026

---

## Executive Summary

Enable users to organize Stacks with tags for categorization and filtering. Tags are globally unique identifiers that persist across the app, allowing users to group related work and quickly filter their home view. The system provides autocomplete suggestions when adding tags and displays them as visual chips throughout the UI.

**Key Decisions:**
- **Tag storage**: Dedicated `Tag` model for global uniqueness and metadata
- **Relationship**: Many-to-many between Stacks and Tags
- **Autocomplete**: Custom SwiftUI implementation with popover suggestions
- **Display**: Capsule-style chips consistent with existing badge patterns
- **Filtering**: Tag filter bar on Home view
- **Tag browser**: New section in Settings or dedicated tab
- **Colors**: Optional user-assigned colors per tag (Phase 2)
- **Case handling**: Case-insensitive matching, preserve original case

---

## 1. Overview

### 1.1 Problem Statement

Users accumulate many Stacks over time representing different areas of their life (work projects, personal tasks, errands, creative endeavors). Currently, there's no way to:
- Categorize Stacks by domain or project
- Filter the home view to focus on specific areas
- See at a glance what category a Stack belongs to
- Find all Stacks related to a particular topic

This forces users to rely on naming conventions or mental models to organize their work.

### 1.2 Proposed Solution

Implement a tagging system that allows users to:
- Add one or more tags to any Stack
- See tags displayed as chips on Stack rows
- Filter the Home view by one or more tags
- Browse all tags and see Stacks grouped by tag
- Get autocomplete suggestions when typing tag names
- Create new tags on-the-fly while tagging

### 1.3 Goals

- Enable intuitive tag assignment with minimal friction
- Provide fast autocomplete for existing tags
- Display tags prominently without cluttering the UI
- Support filtering by single or multiple tags
- Maintain offline-first behavior with eventual sync
- Emit events for all tag operations

### 1.4 Non-Goals

- Hierarchical/nested tags (keep it flat and simple)
- Tag-based automation or smart rules
- Sharing tags across users
- Tag templates or presets
- Mandatory tagging (tags are always optional)
- Tagging individual Tasks (Stacks only for v1)

---

## 2. User Stories

### 2.1 Primary User Stories

1. **As a user**, I want to add tags to a Stack when creating it, so I can categorize from the start.
2. **As a user**, I want to add/remove tags when editing a Stack, so I can recategorize as needed.
3. **As a user**, I want to see existing tags suggested as I type, so I don't create duplicates.
4. **As a user**, I want to create a new tag by typing a name that doesn't exist, so I'm not limited to predefined tags.
5. **As a user**, I want to see tag chips on each Stack in the home view, so I can quickly identify categories.
6. **As a user**, I want to filter my home view by tag, so I can focus on specific areas.
7. **As a user**, I want to browse all my tags and see Stacks grouped by them, so I can explore my organization.
8. **As a user**, I want my tags to sync across all my devices, so my organization is consistent.

### 2.2 Edge Cases

- User creates tag offline → syncs when online, deduplicates if same tag created on another device
- User deletes all Stacks with a tag → tag persists (can be cleaned up manually)
- User types tag with different casing → matches existing tag case-insensitively
- User adds same tag twice to a Stack → prevented (no duplicates per Stack)
- Very long tag name → truncate display with ellipsis, full name on tap

---

## 3. Technical Design

### 3.1 Data Model

#### 3.1.1 Tag Model (New SwiftData Entity)

```swift
@Model
final class Tag {
    @Attribute(.unique) var id: String
    var name: String                    // Display name (case-preserved)
    var normalizedName: String          // Lowercase for matching
    var colorHex: String?               // Optional: user-assigned color (Phase 2)
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    // Sync fields
    var userId: String?
    var deviceId: String?
    var syncState: SyncState
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int

    // Relationship
    @Relationship(inverse: \Stack.tagObjects)
    var stacks: [Stack] = []

    init(
        id: String = CUID.generate(),
        name: String,
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
        self.name = name
        self.normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.userId = userId
        self.deviceId = deviceId
        self.syncState = syncState
        self.lastSyncedAt = lastSyncedAt
        self.serverId = serverId
        self.revision = revision
    }
}

extension Tag {
    /// Count of non-deleted Stacks using this tag
    var activeStackCount: Int {
        stacks.filter { !$0.isDeleted && $0.status == .active }.count
    }
}
```

#### 3.1.2 Stack Model Updates

```swift
@Model
final class Stack {
    // ... existing fields ...

    // Replace tags: [String] with relationship
    @Relationship(deleteRule: .nullify)
    var tagObjects: [Tag] = []

    // Convenience computed property
    var tagNames: [String] {
        tagObjects.filter { !$0.isDeleted }.map { $0.name }
    }
}
```

**Migration Note**: The existing `tags: [String]` field will be migrated to the new relationship. For each unique string in existing tags, create a Tag entity if not exists, then link.

#### 3.1.3 Backend Event Schema

```json
{
  "id": "evt_abc123",
  "type": "tag.created",
  "ts": "2026-01-03T10:30:00.000Z",
  "device_id": "device_xyz",
  "payload": {
    "tagId": "tag_123",
    "state": {
      "id": "tag_123",
      "name": "Work",
      "normalizedName": "work",
      "colorHex": null,
      "createdAt": 1704278400000,
      "updatedAt": 1704278400000,
      "deleted": false
    }
  }
}
```

### 3.2 Event Types

| Event Type | Description | Payload |
|------------|-------------|---------|
| `tag.created` | New tag created | Full tag state |
| `tag.updated` | Tag renamed or color changed | Full tag state |
| `tag.deleted` | Tag soft-deleted | tagId, timestamp |
| `stack.tagAdded` | Tag associated with Stack | stackId, tagId |
| `stack.tagRemoved` | Tag disassociated from Stack | stackId, tagId |

**Note**: `stack.tagAdded` and `stack.tagRemoved` are separate from `stack.updated` to enable fine-grained sync and conflict resolution.

### 3.3 Service Layer

#### 3.3.1 TagService (New)

```swift
actor TagService {
    private let modelContext: ModelContext
    private let eventService: EventService

    /// Fetch all non-deleted tags, sorted by name
    func fetchAllTags() async throws -> [Tag]

    /// Find or create a tag by name (case-insensitive match)
    func findOrCreateTag(name: String) async throws -> Tag

    /// Search tags matching prefix (for autocomplete)
    func searchTags(prefix: String, limit: Int = 10) async throws -> [Tag]

    /// Add tag to stack (idempotent)
    func addTagToStack(_ tag: Tag, stack: Stack) async throws

    /// Remove tag from stack
    func removeTagFromStack(_ tag: Tag, stack: Stack) async throws

    /// Delete orphaned tags (no stacks using them)
    func cleanupOrphanedTags() async throws -> Int

    /// Rename tag (updates all references)
    func renameTag(_ tag: Tag, to newName: String) async throws
}
```

### 3.4 Offline-First Behavior

1. **Creating a tag offline**:
   - Tag created locally with `syncState: .pending`
   - On sync: if server has same `normalizedName`, merge to server's tag ID
   - Emit `tag.created` event

2. **Adding tag to Stack offline**:
   - Relationship created locally
   - Emit `stack.tagAdded` event with `syncState: .pending`
   - On sync: resolve tag ID if it was deduplicated

3. **Conflict resolution**:
   - Tag names: LWW on `updatedAt`
   - Tag-Stack relationships: Union merge (if either device has it, keep it)
   - Deleted tags: LWW (can be re-created if needed)

### 3.5 Autocomplete Implementation

```
┌─────────────────────────────────────────┐
│ TextField: "wor"                     [x]│
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ Work                            (3) │ │  ← Existing tag, 3 stacks
│ ├─────────────────────────────────────┤ │
│ │ Workout                         (1) │ │  ← Existing tag, 1 stack
│ ├─────────────────────────────────────┤ │
│ │ + Create "wor"                      │ │  ← Create new tag option
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**Autocomplete Logic**:
1. Query tags where `normalizedName` starts with input (lowercased)
2. Sort by usage count (most used first), then alphabetically
3. Limit to 5-10 suggestions
4. Always show "Create new" option if exact match doesn't exist
5. Debounce input by 150ms to reduce queries

---

## 4. UI/UX Design

### 4.1 Tag Input Component

A reusable `TagInputView` component used in both create and edit modes:

```
┌─────────────────────────────────────────┐
│ Tags                                    │
│ ┌───────┐ ┌────────┐ ┌─────────────────┐│
│ │Work ×│ │Personal×│ │ Add tag...     ││
│ └───────┘ └────────┘ └─────────────────┘│
└─────────────────────────────────────────┘
```

**Behavior**:
- Existing tags shown as removable chips
- Text field at end for adding new tags
- Tapping text field shows autocomplete popover
- Typing filters suggestions
- Tapping suggestion or pressing Enter adds tag
- Tapping × on chip removes tag
- Chips wrap to multiple lines if needed

**Component Signature**:
```swift
struct TagInputView: View {
    @Binding var selectedTags: [Tag]
    let allTags: [Tag]  // For autocomplete
    let onTagAdded: (Tag) -> Void
    let onTagRemoved: (Tag) -> Void
    let onNewTagCreated: (String) -> Tag
}
```

### 4.2 Tag Chip Component

Consistent capsule styling matching existing badges:

```swift
struct TagChip: View {
    let tag: Tag
    let showRemoveButton: Bool
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            // Optional: colored dot if tag has color
            if let colorHex = tag.colorHex {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 6, height: 6)
            }

            Text(tag.name)
                .font(.caption)
                .lineLimit(1)

            if showRemoveButton {
                Button(action: { onRemove?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15))
        .foregroundStyle(.secondary)
        .clipShape(Capsule())
    }
}
```

### 4.3 Stack Row with Tags

Updated `StackRowView` to display tags:

```
┌─────────────────────────────────────────┐
│ Quarterly Report                      ★ │
│ Draft executive summary                 │
│ 🔔 2                                    │
│ ┌────┐ ┌──────────┐                     │
│ │Work│ │Q1 Planning│                    │
│ └────┘ └──────────┘                     │
└─────────────────────────────────────────┘
```

**Implementation**:
- Show up to 3 tags inline
- If more than 3, show "+N more" indicator
- Tags shown below reminders row
- Chips are non-interactive in list view (just display)

### 4.4 Home View Filtering

Add a horizontal scrollable filter bar below the navigation title:

```
┌─────────────────────────────────────────┐
│ Dequeue                              🔔 │
├─────────────────────────────────────────┤
│ ┌───┐ ┌────┐ ┌────────┐ ┌─────────┐     │
│ │All│ │Work│ │Personal│ │Q1 Plann…│ ... │
│ └───┘ └────┘ └────────┘ └─────────┘     │
├─────────────────────────────────────────┤
│ Stack 1...                              │
│ Stack 2...                              │
└─────────────────────────────────────────┘
```

**Behavior**:
- "All" is default, shows all stacks
- Tapping a tag filters to only stacks with that tag
- Multiple tags can be selected (AND logic or OR logic - decision needed)
- Selected tags are visually highlighted
- Filter persists during session, resets on app restart
- Show tag count in filter chip: "Work (5)"

### 4.5 Tags Browser View

New view accessible from Settings or as dedicated section:

**Option A: Settings Section**
```
Settings
├── Tags                    →
│   └── [Tags Browser View]
├── Devices
└── ...
```

**Option B: Dedicated Tab** (if app grows)

**Tags Browser View Layout**:
```
┌─────────────────────────────────────────┐
│ Tags                                    │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ Work                            (5) │→│
│ ├─────────────────────────────────────┤ │
│ │ Personal                        (3) │→│
│ ├─────────────────────────────────────┤ │
│ │ Q1 Planning                     (2) │→│
│ ├─────────────────────────────────────┤ │
│ │ Errands                         (1) │→│
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**Tapping a tag** → Shows list of Stacks with that tag:
```
┌─────────────────────────────────────────┐
│ ← Work                            Edit  │
├─────────────────────────────────────────┤
│ 5 stacks                                │
├─────────────────────────────────────────┤
│ Quarterly Report                        │
│ Client Proposal                         │
│ Team Sync Prep                          │
│ ...                                     │
└─────────────────────────────────────────┘
```

**Edit mode** allows:
- Rename tag
- Change tag color (Phase 2)
- Delete tag (with confirmation)

### 4.6 Platform Considerations

**iOS/iPadOS**:
- Tag filter bar as horizontal ScrollView
- Autocomplete as sheet on iPhone, popover on iPad
- Support keyboard navigation for autocomplete

**macOS**:
- Tag filter bar in toolbar or sidebar
- Autocomplete as popover below text field
- Support keyboard shortcuts: ⌘T to focus tag input

---

## 5. Backend Changes

### 5.1 New Database Table

```sql
CREATE TABLE tags (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    color_hex TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted BOOLEAN NOT NULL DEFAULT FALSE,
    revision INTEGER NOT NULL DEFAULT 1
);

CREATE UNIQUE INDEX idx_tags_user_normalized ON tags(user_id, normalized_name)
    WHERE deleted = FALSE;

CREATE TABLE stack_tags (
    stack_id TEXT NOT NULL REFERENCES stacks(id),
    tag_id TEXT NOT NULL REFERENCES tags(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (stack_id, tag_id)
);

CREATE INDEX idx_stack_tags_tag ON stack_tags(tag_id);
```

### 5.2 Event Handling

Add handling for new event types:
- `tag.created` → Insert into `tags` table
- `tag.updated` → Update `tags` row
- `tag.deleted` → Set `deleted = true`
- `stack.tagAdded` → Insert into `stack_tags`
- `stack.tagRemoved` → Delete from `stack_tags`

### 5.3 Sync Considerations

- Tags sync independently from Stacks
- `stack.tagAdded` events reference tag by ID
- If tag doesn't exist on device during sync, fetch it first
- Tag deduplication by `normalized_name` during sync

---

## 6. Open Questions

These questions need resolution before implementation:

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| 1 | Multiple tag filter logic | AND (all tags) vs OR (any tag) | OR is more intuitive for filtering |
| 2 | Tag input UI library | Custom vs KSTokenView vs other | Custom for full control, but evaluate KSTokenView first |
| 3 | Tag browser location | Settings section vs dedicated tab | Settings section for v1, can promote later |
| 4 | Tag colors in v1? | Include vs defer | Defer to Phase 2, adds complexity |
| 5 | Tag character limit | None vs 30 chars vs 50 chars | 30 chars max, prevents abuse |
| 6 | Tag count on Home filter | Show count vs hide | Show count: "Work (5)" |
| 7 | Empty tag state | Allow vs prevent | Prevent empty/whitespace-only tags |
| 8 | Case preservation | First-usage wins vs most-recent | First-usage wins (stable display) |

---

## 7. Decisions Made

| Question | Decision | Rationale |
|----------|----------|-----------|
| Tag storage model | Dedicated `Tag` entity | Enables global uniqueness, autocomplete, counts, future colors |
| Relationship type | Many-to-many via SwiftData | A Stack can have multiple tags; a Tag can be on multiple Stacks |
| Event granularity | Separate `stack.tagAdded/Removed` | Fine-grained sync, cleaner conflict resolution |
| Autocomplete debounce | 150ms | Responsive without excessive queries |
| Max tags per Stack | No limit | Let users organize as they see fit |
| Tag case handling | Case-insensitive match, preserve original | "Work" and "work" are the same tag |
| Orphan tag handling | Keep orphaned tags | User may want to reuse; can clean up manually |

---

## 8. Success Metrics

- Users can successfully add tags while offline
- Tags sync correctly across devices
- Autocomplete shows relevant suggestions within 200ms
- Tag filtering correctly shows/hides Stacks
- No duplicate tags created (case-insensitive)
- Tag operations don't impact list scrolling performance

---

## 9. Implementation Phases

### Phase 1: Data Model & Core Service

**iOS (dequeue-ios):**
- Create `Tag` SwiftData model
- Update `Stack` model with `tagObjects` relationship
- Write migration from `tags: [String]` to relationship
- Create `TagService` with CRUD operations
- Add `tag.created`, `tag.updated`, `tag.deleted` to `EventType` enum
- Add `stack.tagAdded`, `stack.tagRemoved` to `EventType` enum
- Update `EventService` with tag event recording
- Update `ProjectorService` to handle tag events
- Write unit tests for TagService

**Backend (stacks-sync):**
- Add `tags` and `stack_tags` tables (migration)
- Add event type handling for tag events
- Update sync logic for tag deduplication

### Phase 2: Tag Input UI Component

**iOS:**
- Create `TagChip` view component
- Create `TagInputView` with autocomplete
- Create autocomplete popover/sheet UI
- Implement debounced search
- Test on iOS and macOS

### Phase 3: Stack Editor Integration

**iOS:**
- Add `TagInputView` to `StackEditorView` create mode
- Add `TagInputView` to `StackEditorView` edit mode
- Wire up tag add/remove actions to TagService
- Emit events on tag operations
- Update previews

### Phase 4: Home View Display & Filtering

**iOS:**
- Update `StackRowView` to display tag chips
- Add tag filter bar to `HomeView`
- Implement filter state management
- Update Stack query to support tag filtering
- Handle empty state when filter has no results

### Phase 5: Tags Browser

**iOS:**
- Create `TagsListView` showing all tags with counts
- Create `TagDetailView` showing Stacks for a tag
- Add tag rename functionality
- Add tag delete with confirmation
- Add navigation from Settings

### Phase 6: Polish & Edge Cases

- Performance optimization for large tag counts
- Keyboard navigation for autocomplete
- VoiceOver accessibility
- Tag input focus management
- Animation polish

### Phase 7 (Future): Tag Colors

- Add color picker to tag edit
- Update `TagChip` to display colors
- Sync colors across devices

---

## 10. Dependencies

- SwiftData relationship support (iOS 17+)
- Existing event system infrastructure
- Backend sync service updates

---

## 11. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Autocomplete performance with many tags | Medium | Limit results to 10; use `normalizedName` index; debounce |
| Tag deduplication conflicts during sync | Medium | Use `normalizedName` as canonical key; merge by first-created |
| Complex migration from `[String]` to entities | High | Write comprehensive migration tests; support rollback |
| SwiftData relationship performance | Medium | Lazy load tag relationships; batch operations |
| Tag input UX complexity | Medium | Start simple; iterate based on user feedback |
| Filter state persistence | Low | Session-only for v1; can add persistence later |

---

## Appendix A: UI Component Library Evaluation

Several SwiftUI tag/token input libraries were evaluated:

| Library | Pros | Cons | Verdict |
|---------|------|------|---------|
| [SwiftUIChipGroup](https://github.com/Open-Bytes/SwiftUIChipGroup) | Simple, customizable | Display only, no input | Not suitable |
| [TokenTextField_SwiftUI](https://github.com/JayantBadlani/TokenTextField_SwiftUI) | Token input, Mail-like | No autocomplete, minimal maintenance | Possible base |
| [KSTokenView](https://www.cocoacontrols.com/controls/kstokenview-swift) | Full-featured, autocomplete | UIKit-based, needs wrapping | Evaluate |
| Custom implementation | Full control, SwiftUI native | Development time | Recommended |

**Recommendation**: Build custom implementation using SwiftUI. The autocomplete UX is specific enough that a custom solution will provide better integration with our design system and event architecture. Can reference TokenTextField_SwiftUI patterns for chip layout.

---

## Appendix B: Example User Flows

### Flow 1: Adding a Tag to a New Stack

1. User taps "+" to create new Stack
2. User enters Stack title
3. User taps "Add tag..." field
4. Autocomplete popover appears with existing tags
5. User types "wo" → sees "Work", "Workout", "+ Create 'wo'"
6. User taps "Work"
7. "Work" chip appears in tag input
8. User taps "Create" to publish Stack
9. Events emitted: `stack.created`, `stack.tagAdded`

### Flow 2: Filtering Home by Tag

1. User views Home with 10 Stacks
2. User taps "Work" in filter bar
3. List filters to 5 Stacks tagged "Work"
4. Filter chip shows selected state
5. User taps "Work" again to deselect
6. All 10 Stacks visible again

### Flow 3: Browsing Tags

1. User opens Settings → Tags
2. Sees list: "Work (5)", "Personal (3)", "Errands (1)"
3. User taps "Work"
4. Sees 5 Stacks with "Work" tag
5. User taps "Edit"
6. Can rename tag or delete it
7. Renaming updates all 5 Stacks' display

---

## Appendix C: Accessibility Considerations

- All tag chips have accessibility labels: "Tag: Work, remove button"
- Autocomplete list is navigable via VoiceOver
- Filter bar announces selected state changes
- Tag input announces "suggestion: Work, 3 stacks" when focused
- Delete confirmations are accessible alerts
