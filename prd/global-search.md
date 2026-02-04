# Global Search - PRD

**Feature:** Global Search  
**Author:** Ada (Dequeue Engineer)  
**Date:** 2026-02-03  
**Status:** Draft  
**Related:** ROADMAP.md Section 7

## Problem Statement

As users accumulate hundreds of Stacks and thousands of Tasks over months of use, finding specific items becomes increasingly painful. Currently, users must:
- Scroll through the Stack list hoping to spot what they need
- Remember which Stack contains a specific Task
- Manually browse through Completed, Active, and Archived sections
- Give up and recreate items they know exist but can't find

This friction compounds over time and makes the app feel slow and frustrating for power users.

**User quotes (anticipated):**
- "I know I have a stack about API integration, but I can't find it"
- "There was a task about buying sheets... where did I put that?"
- "I have 200 stacks, scrolling is not working anymore"

## Solution

A unified, instant search experience that queries across all Stacks and Tasks with smart ranking and filtering.

**Key Principles:**
1. **Fast**: Sub-100ms response time for typical queries
2. **Comprehensive**: Search all entities (Stacks, Tasks, future: Attachments, Links)
3. **Offline-first**: No network required, all local SwiftData queries
4. **Smart ranking**: Relevant results first (active > recent > older)
5. **Accessible**: Keyboard shortcut on macOS, prominent on iOS

## User Experience

### Entry Points

**iOS:**
- Search bar at top of Stacks tab (always visible, collapses on scroll)
- Pull down on Stack list reveals search bar (iOS standard pattern)

**macOS:**
- Search bar in toolbar (always visible)
- Keyboard shortcut: ⌘F (activates search, focuses input field)

### Search Flow

1. User taps/focuses search bar
2. Search UI expands to full screen
3. Recent searches shown as suggestions (if any)
4. As user types, results appear instantly
5. Results grouped by entity type: Stacks, Tasks
6. Each result shows:
   - Entity title (with matched text highlighted)
   - Parent context (for Tasks: "in [Stack Name]")
   - Status badge (Active, Completed, Archived)
   - Last modified timestamp
7. Tap result → Navigate to detail view
8. Clear button (X) to reset search

### Result Ranking

**Priority order:**
1. **Exact title match** (case-insensitive)
2. **Active items** (either Active Stack or Task in Active Stack)
3. **Recent items** (modified in last 7 days)
4. **Partial match** (substring in title)
5. **Description match** (lower priority than title)

**Example:**
Search: "api"
Results:
1. Stack: "API Integration" (exact match, active) ⭐
2. Task: "Test API endpoint" (in Active Stack, recent)
3. Stack: "Rapid API Research" (partial match)
4. Task: "Update API docs" (in completed Stack, older)

### Scope Filters

Toggle buttons above results:
- **All** (default)
- **Active Only** (Stacks that are Active OR Tasks in Active Stacks)
- **Completed** (completed/archived items)
- **Stacks Only**
- **Tasks Only**

### Empty States

**No query entered:**
- Show recent searches (up to 5)
- Suggestion chips: "Active tasks", "Completed this week"

**No results:**
- "No results for '[query]'"
- Suggestion: "Try searching for a different term"
- Option to create new Stack/Task with query as title

### Recent Searches

- Store last 10 unique search queries
- Persist in UserDefaults (not synced across devices)
- Display as tappable chips when search bar is focused
- Clear individual or clear all

## Technical Design

### SwiftData Query

**Core search predicate:**
```swift
func searchPredicate(query: String) -> Predicate<Stack> {
    let lowercaseQuery = query.lowercased()
    return #Predicate<Stack> { stack in
        stack.title.localizedStandardContains(lowercaseQuery) ||
        (stack.stackDescription ?? "").localizedStandardContains(lowercaseQuery)
    }
}

func searchTasksPredicate(query: String) -> Predicate<Task> {
    let lowercaseQuery = query.lowercased()
    return #Predicate<Task> { task in
        task.title.localizedStandardContains(lowercaseQuery) ||
        (task.taskDescription ?? "").localizedStandardContains(lowercaseQuery) ||
        (task.blockedReason ?? "").localizedStandardContains(lowercaseQuery)
    }
}
```

**Optimization:**
- Debounce input by 150ms to avoid excessive queries while typing
- Limit results to 50 per entity type (pagination if needed later)
- Use `@Query` with dynamic predicate for reactive updates

### Search Result Model

```swift
struct SearchResult: Identifiable {
    let id: UUID
    let type: SearchResultType
    let title: String
    let subtitle: String?  // Parent Stack for Tasks
    let status: EntityStatus
    let lastModified: Date
    let matchScore: Int  // For ranking
    
    // Navigation
    let stackId: UUID?
    let taskId: UUID?
}

enum SearchResultType {
    case stack
    case task
}

enum EntityStatus {
    case active
    case pending
    case completed
    case archived
}
```

### Ranking Algorithm

```swift
func calculateMatchScore(
    entity: any Searchable,
    query: String,
    isActive: Bool,
    lastModified: Date
) -> Int {
    var score = 0
    
    // Exact title match: +100
    if entity.title.localizedStandardCompare(query) == .orderedSame {
        score += 100
    }
    
    // Title contains query: +50
    if entity.title.localizedStandardContains(query) {
        score += 50
    }
    
    // Active: +30
    if isActive {
        score += 30
    }
    
    // Recent (last 7 days): +20
    let daysSinceModified = Calendar.current.dateComponents(
        [.day], 
        from: lastModified, 
        to: Date()
    ).day ?? Int.max
    if daysSinceModified <= 7 {
        score += 20
    }
    
    // Description match: +10
    if entity.description?.localizedStandardContains(query) == true {
        score += 10
    }
    
    return score
}
```

### View Architecture

**New Views:**
1. `SearchView` (main container)
2. `SearchBar` (text field with clear button)
3. `SearchResultsList` (grouped results)
4. `SearchResultRow` (individual result cell)
5. `RecentSearchesView` (chips for recent queries)

**ViewModel:**
```swift
@Observable
class SearchViewModel {
    var query: String = ""
    var recentSearches: [String] = []
    var activeFilter: SearchFilter = .all
    var isSearching: Bool = false
    
    // Computed
    var stackResults: [SearchResult] = []
    var taskResults: [SearchResult] = []
    var allResults: [SearchResult] {
        (stackResults + taskResults).sorted { $0.matchScore > $1.matchScore }
    }
    
    func search(query: String) async {
        // Debounce, fetch, rank, update results
    }
    
    func addRecentSearch(_ query: String) {
        // Store in UserDefaults
    }
    
    func clearRecentSearches() {
        // Clear UserDefaults
    }
}
```

### Performance Considerations

**Optimization Strategies:**
1. **Index-free design**: Rely on SwiftData's built-in indexing (title, description auto-indexed)
2. **Debouncing**: Wait 150ms after last keystroke before querying
3. **Limit results**: Max 50 Stacks + 50 Tasks returned
4. **Lazy loading**: Use `LazyVStack` for result list
5. **Background queries**: Run search on background thread if needed (SwiftData handles this)

**Scaling:**
- Should be fast up to ~1,000 Stacks and ~10,000 Tasks
- If performance degrades, consider FTS (full-text search) via external index

### Keyboard Shortcuts (macOS)

```swift
.keyboardShortcut("f", modifiers: .command)
```

Registers ⌘F globally in app to focus search bar.

## Acceptance Criteria

### Functional
- [ ] Search bar visible on Stacks tab (iOS) and toolbar (macOS)
- [ ] ⌘F keyboard shortcut activates search on macOS
- [ ] Query debounced to 150ms (no query on every keystroke)
- [ ] Results include Stacks and Tasks matching query
- [ ] Results grouped by entity type
- [ ] Matched text highlighted in results
- [ ] Tap result navigates to detail view
- [ ] Filter toggles work (All, Active, Completed, Stacks, Tasks)
- [ ] Recent searches stored and displayed
- [ ] Clear button resets search
- [ ] Empty state for no results
- [ ] Works fully offline (no network required)

### Performance
- [ ] Search completes in <100ms for typical query (10-character substring)
- [ ] No UI lag while typing
- [ ] Smooth scrolling in results list
- [ ] Fast enough with 1,000 Stacks and 10,000 Tasks

### Design
- [ ] iOS: Follows iOS search bar conventions (collapsible, pull-to-reveal)
- [ ] macOS: Toolbar search field with standard appearance
- [ ] Matched text visibly highlighted
- [ ] Status badges clear and consistent with rest of app
- [ ] Keyboard navigation works (arrow keys, Enter to select)

## Edge Cases

1. **Very long titles**: Truncate with ellipsis, show full on tap
2. **Special characters in query**: Handle gracefully (no crashes)
3. **Empty query**: Show recent searches, don't execute search
4. **No recent searches**: Show suggestion chips instead
5. **Deleted entities in recent searches**: Handle stale references gracefully
6. **Query while syncing**: May get partial results (expected, offline-first)
7. **Case sensitivity**: Always case-insensitive (per UX standard)
8. **Leading/trailing whitespace**: Trim before searching

## Future Enhancements

**Phase 2:**
- Search Attachments by filename
- Search Links by URL/title
- Fuzzy matching ("apii" → "api")
- Search Tags
- Filter by Tag
- Date range filters ("completed last week")

**Phase 3:**
- Full-text search index for faster queries at scale
- Search history sync across devices
- Natural language queries ("tasks I completed yesterday")
- Saved searches / Smart filters

**Phase 4:**
- Search voice dictation (iOS)
- Spotlight integration (iOS/macOS system search)
- Search within attachments (OCR for images, text extraction for PDFs)

## Implementation Plan

**Estimated: 1-2 days**

### Day 1: Core Search (6-8 hours)
1. Create `SearchViewModel` with debounced query logic (1 hour)
2. Implement SwiftData search predicates for Stacks and Tasks (1 hour)
3. Build `SearchView` UI (search bar + results list) (2 hours)
4. Implement result ranking algorithm (1 hour)
5. Add navigation from result tap (30 min)
6. Test with sample data (30 min)

### Day 2: Polish & Filters (4-6 hours)
1. Add filter toggles (All, Active, Completed, etc.) (1 hour)
2. Recent searches storage + UI (1 hour)
3. Keyboard shortcut on macOS (30 min)
4. Empty states and error handling (1 hour)
5. Unit tests for search logic and ranking (1 hour)
6. UI tests for search flow (30 min)
7. PR review & merge (1 hour + CI time)

**Total: 10-14 hours** (spread across 2 days with buffer for testing/polish)

## Dependencies

- ✅ SwiftData models already have title, description fields
- ✅ No backend changes required (fully local)
- ✅ No new dependencies needed

**No blockers - ready to implement immediately.**

## Out of Scope

- Syncing search history across devices (UserDefaults only)
- Fuzzy matching (exact substring only)
- Attachment/Link search (Phase 2)
- Natural language parsing (Phase 3)
- Spotlight integration (Phase 4)

## Testing Strategy

### Unit Tests
```swift
@Test func searchFindsExactTitleMatch() async throws {
    let stack = Stack(title: "API Integration", ...)
    await modelContext.insert(stack)
    
    let results = await searchViewModel.search(query: "API Integration")
    #expect(results.count == 1)
    #expect(results.first?.title == "API Integration")
}

@Test func searchFindsPartialMatch() async throws {
    let stack = Stack(title: "API Integration", ...)
    await modelContext.insert(stack)
    
    let results = await searchViewModel.search(query: "api")
    #expect(results.count == 1)
}

@Test func searchRanksActiveHigher() async throws {
    let activeStack = Stack(title: "Active API", isActive: true, ...)
    let inactiveStack = Stack(title: "Old API", isActive: false, ...)
    await modelContext.insert(activeStack)
    await modelContext.insert(inactiveStack)
    
    let results = await searchViewModel.search(query: "api")
    #expect(results.first?.title == "Active API")
}

@Test func searchIsCaseInsensitive() async throws {
    let stack = Stack(title: "API Integration", ...)
    await modelContext.insert(stack)
    
    let results = await searchViewModel.search(query: "api integration")
    #expect(results.count == 1)
}
```

### Integration Tests
- Create 100 Stacks and 500 Tasks
- Search for common terms, verify results
- Verify performance <100ms
- Test filter toggles
- Test navigation from results

### Manual Testing
- Search with various queries (short, long, special chars)
- Verify ranking makes sense
- Test on device with large dataset (1000+ items)
- Test keyboard shortcut on macOS
- Test accessibility (VoiceOver)

## Success Metrics

**Adoption:**
- % of users who use search in first week
- % of sessions that include a search

**Engagement:**
- Average searches per user per day
- Success rate (search → result tap)
- Time to find item (before vs after search)

**Performance:**
- P50/P95 search latency
- Search latency vs dataset size

**Target:**
- 50%+ of weekly active users try search in first month
- <100ms P95 latency on devices with 1,000+ items
- 70%+ success rate (user taps a result)

---

**Next Steps:**
1. Review PRD with Victor
2. Create implementation ticket (DEQ-XXX)
3. Implement when CI is responsive
4. Ship and gather user feedback

Search is a high-leverage feature that dramatically improves UX for power users. Let's ship it!
