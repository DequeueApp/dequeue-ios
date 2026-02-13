# PRD: iPad Split View

**Status:** ✅ IMPLEMENTED  
**Priority:** 2  
**Ticket:** DEQ-51 (was DEQ-238)  
**Implementation:** PR #256 (merged February 10, 2026)  
**Author:** Ada  
**Created:** 2026-02-04  
**Completed:** 2026-02-10  

---

## ✅ Implementation Summary

**What was implemented:**
- NavigationSplitView for iPad with sidebar + detail layout
- Responsive behavior: iPad landscape (always visible), iPad portrait (collapsible), iPhone (no split)
- Sidebar shows list of stacks with selection highlighting
- Detail pane shows selected stack's full editor
- Conditional compilation guards for iOS vs macOS
- State preservation across app launches
- Smooth animations and transitions

**Key changes:**
- `MainTabView.swift`: Added `isPad` detection and conditional layouts
- Separate `iPhoneTabViewLayout` and `iPadSplitViewLayout` computed properties
- `#if os(iOS)` guards for iOS-specific modifiers
- Navigation state management for selection

**Result:** iPad users now have a native split-view experience matching iOS conventions.

---

## Problem Statement

### Current State
Dequeue iOS uses a simple list-based UI on iPad, identical to iPhone. This wastes iPad's large screen real estate and doesn't match user expectations for iPad apps.

### User Pain Points
- **Wasted screen space:** iPad users see the same narrow list view as iPhone users
- **Extra taps required:** Must navigate back/forth between list and detail views
- **Inconsistent with iPad conventions:** Most productivity apps use split views on iPad
- **Poor multitasking experience:** Doesn't adapt well to iPad split-screen/Stage Manager

### Competitive Analysis
- **Todoist, Things 3, OmniFocus:** All use split views on iPad
- **Apple Reminders:** Uses sidebar + detail pane on iPad
- **Industry standard:** Split view is expected for productivity apps on iPad

## Solution: Adaptive Split View

Implement a master-detail split view layout that:
1. Shows list of stacks/tasks in the sidebar (primary)
2. Shows selected stack detail in the main area (secondary)
3. Adapts to iPhone (no split), iPad Portrait (collapsible), iPad Landscape (always visible)
4. Persists selection across app launches
5. Supports keyboard navigation

## Technical Design

### SwiftUI NavigationSplitView

**Core Implementation:**
```swift
struct MainTabView: View {
    #if os(iOS)
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    #endif
    
    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        if isIPad {
            iPadLayout
        } else {
            iPhoneLayout
        }
        #endif
    }
    
    private var iPadLayout: some View {
        NavigationSplitView {
            // Sidebar: List of stacks/arcs
            sidebarContent
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 600)
        } detail: {
            // Detail: Selected stack or empty state
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
    }
}
```

### Architecture Changes

**1. Navigation State Management**
```swift
@Observable
class NavigationState {
    var selectedStack: Stack?
    var selectedArc: Arc?
    var detailMode: DetailMode = .empty
    
    enum DetailMode {
        case empty
        case stack(Stack)
        case arc(Arc)
    }
}
```

**2. Sidebar Content**
- Segmented picker: Stacks / Arcs / Activity
- Filtered list based on selection
- Search bar at top
- Refresh control
- Selection highlights

**3. Detail Content**
- Stack editor (when stack selected)
- Arc editor (when arc selected)
- Empty state with helpful message
- Toolbar actions (edit, complete, delete)

### iPad-Specific Features

**Split View Modes:**
- **iPhone:** Traditional NavigationStack (no split)
- **iPad Portrait:** Collapsible sidebar (overlay mode)
- **iPad Landscape:** Persistent sidebar (side-by-side mode)
- **iPad Split Screen:** Adapts column widths automatically

**Keyboard Shortcuts (iPad):**
- `Cmd+1` / `Cmd+2` / `Cmd+3`: Switch tabs (Stacks/Arcs/Activity)
- `Cmd+N`: New stack/arc (context-aware)
- `Cmd+F`: Focus search
- `Cmd+Up`/`Down`: Navigate list
- `Return`: Open selected item

### Persistence

**User Defaults:**
```swift
struct NavigationPreferences {
    var lastSelectedStackId: String?
    var lastSelectedArcId: String?
    var sidebarTab: SidebarTab = .stacks
    
    enum SidebarTab: String {
        case stacks, arcs, activity
    }
}
```

**On Launch:**
1. Restore last selected tab
2. Restore last selected stack/arc (if still exists)
3. Show detail view if selection valid
4. Otherwise show empty state

## Implementation Plan

### Phase 1: Basic Split View (Day 1)
- [ ] Add `NavigationSplitView` wrapper for iPad
- [ ] Create `SidebarView` component
- [ ] Create `DetailView` component
- [ ] Implement stack selection
- [ ] Test on iPad Simulator

### Phase 2: Navigation State (Day 1-2)
- [ ] Create `NavigationState` observable
- [ ] Wire up selection binding
- [ ] Implement empty state
- [ ] Add selection persistence
- [ ] Test state restoration

### Phase 3: Polish & Adaptation (Day 2-3)
- [ ] Add keyboard shortcuts
- [ ] Implement search in sidebar
- [ ] Test iPad multitasking modes
- [ ] Optimize column widths
- [ ] Add animations/transitions

### Phase 4: Arc Support (Day 3)
- [ ] Add Arc selection support
- [ ] Implement Arc detail view in split
- [ ] Add Arc-specific actions

### Phase 5: Testing & Refinement (Day 4)
- [ ] Test all iPad sizes (9.7", 11", 12.9")
- [ ] Test orientation changes
- [ ] Test multitasking (Split View, Slide Over, Stage Manager)
- [ ] Accessibility testing
- [ ] Performance testing

## Acceptance Criteria

### Functional
- [ ] iPad shows split view with sidebar + detail
- [ ] iPhone continues to use existing navigation
- [ ] Stack selection shows detail in main area
- [ ] Arc selection shows detail in main area
- [ ] Empty state when nothing selected
- [ ] Selection persists across app restarts
- [ ] Search works in sidebar

### UX
- [ ] Sidebar collapses in portrait (overlay mode)
- [ ] Sidebar persists in landscape (side-by-side)
- [ ] Smooth animations between selections
- [ ] Keyboard shortcuts functional
- [ ] Works in iPad multitasking modes

### Technical
- [ ] No regressions on iPhone
- [ ] macOS layout unchanged
- [ ] Navigation state properly managed
- [ ] Memory-efficient (no leaks)
- [ ] SwiftLint passes
- [ ] Unit tests for navigation state

## Edge Cases

### Empty States
- **No stacks:** Show "Create your first stack" CTA in detail
- **Stack deleted while viewing:** Show empty state, clear selection
- **Filter yields no results:** Show "No results" in sidebar

### Multitasking
- **Split View (50/50):** Sidebar uses minimum width, detail gets remainder
- **Slide Over:** Treat as iPhone (no split view)
- **Stage Manager:** Full split view with adaptive widths

### Orientation Changes
- **Portrait → Landscape:** Expand sidebar from overlay to persistent
- **Landscape → Portrait:** Collapse sidebar to overlay mode
- **Preserve selection:** Don't reset on rotation

### Selection Edge Cases
- **Select same item twice:** No-op (already showing)
- **Deep link while detail open:** Navigate to new item
- **Delete item while viewing:** Close detail, show empty state

## Testing Strategy

### Unit Tests
```swift
func testNavigationStateSelection() {
    let state = NavigationState()
    let stack = Stack(title: "Test")
    state.selectedStack = stack
    XCTAssertEqual(state.detailMode, .stack(stack))
}

func testNavigationStatePersistence() {
    let prefs = NavigationPreferences()
    prefs.lastSelectedStackId = "test-id"
    prefs.save()
    
    let restored = NavigationPreferences.load()
    XCTAssertEqual(restored.lastSelectedStackId, "test-id")
}
```

### UI Tests
```swift
func testSplitViewShowsStackDetail() {
    // Launch on iPad simulator
    app.launch()
    
    // Tap first stack in sidebar
    let firstStack = app.tables.cells.firstMatch
    firstStack.tap()
    
    // Verify detail view shows stack editor
    XCTAssertTrue(app.navigationBars["Stack Editor"].exists)
}

func testSidebarCollapseInPortrait() {
    // Set iPad to portrait
    XCUIDevice.shared.orientation = .portrait
    
    // Verify sidebar is overlay mode
    XCTAssertTrue(app.buttons["Toggle Sidebar"].exists)
}
```

### Manual Testing
- [ ] Test on iPad Air (11")
- [ ] Test on iPad Pro (12.9")
- [ ] Test all orientations
- [ ] Test Split View 50/50
- [ ] Test Slide Over
- [ ] Test Stage Manager
- [ ] Test with VoiceOver
- [ ] Test keyboard navigation
- [ ] Test with external keyboard

## Success Metrics

**Adoption:**
- % of iPad users who engage with split view (vs. iPhone-style nav)
- Average session duration on iPad (expect +20-30%)

**User Satisfaction:**
- NPS improvement for iPad users
- Support tickets about "iPad UI too small" (expect significant drop)

**Performance:**
- No degradation in app launch time
- No memory increase
- Smooth 60fps animations

## Future Enhancements

### Phase 2 Features (Post-MVP)
- **Three-column layout:** Sidebar + List + Detail (iPad Pro only)
- **Drag & drop:** Drag tasks between stacks in split view
- **Picture-in-Picture:** Keep detail visible while browsing sidebar
- **Quick Look:** Hover preview of stacks without selecting

### macOS Alignment
- Ensure iPad split view mirrors macOS sidebar UX
- Shared navigation components where possible

### Advanced Keyboard
- Vim-style navigation (j/k for up/down)
- Quick switcher (Cmd+K)
- Tab between sidebar/detail with keyboard

## Dependencies

**iOS Version:** iOS 16+ (NavigationSplitView)  
**Xcode Version:** Xcode 14+  
**Breaking Changes:** None (iPhone/macOS unchanged)  
**Third-party:** None  

## Risks & Mitigations

**Risk:** Complex state management leads to bugs  
**Mitigation:** Comprehensive unit tests, Observable pattern

**Risk:** Regressions on iPhone  
**Mitigation:** Conditional compilation, thorough iPhone testing

**Risk:** Performance issues with large lists  
**Mitigation:** Virtualized lists (LazyVStack), pagination

**Risk:** iPad multitasking edge cases  
**Mitigation:** Extensive manual testing across modes

## Conclusion

Implementing iPad split view is table stakes for a productivity app. Users expect it, competitors have it, and it significantly improves UX on iPad's large screen. The implementation is straightforward with SwiftUI's NavigationSplitView, and the benefits far outweigh the 3-4 day implementation cost.

**Recommendation:** Implement in next sprint. High ROI, well-defined scope, low risk.
