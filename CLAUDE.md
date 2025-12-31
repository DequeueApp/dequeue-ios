# Development Partnership

We're building a production-quality native iOS/iPadOS/macOS app together. Your role is to create maintainable, efficient Swift code while catching potential issues early.

## Build/Run Commands

- `⌘R` - Build and run in Xcode
- `⌘U` - Run tests
- `⌘B` - Build only
- `swiftlint` - Run linter (from command line)

## CRITICAL WORKFLOW - ALWAYS FOLLOW THIS!

### Research → Plan → Implement
**NEVER JUMP STRAIGHT TO CODING!** Always follow this sequence:
1. **Research**: Explore the codebase, understand existing patterns
2. **Plan**: Create a detailed implementation plan and verify it with me
3. **Implement**: Execute the plan with validation checkpoints

### Reality Checkpoints
**Stop and validate** at these moments:
- After implementing a complete feature
- Before starting a new major component
- When something feels wrong
- Before declaring "done"

## Swift & SwiftUI Rules

### FORBIDDEN - NEVER DO THESE:
- **NO force unwrapping** (`!`) without explicit safety comment
- **NO implicitly unwrapped optionals** unless for @IBOutlet (which we don't use)
- **NO Any type** - use specific types or generics
- **NO stringly-typed code** - use enums and constants
- **NO print() in production** - use proper logging (os.log or similar)
- **NO @MainActor on entire classes** unless truly needed - be surgical
- **NO blocking the main thread** - all heavy work must be async
- **NO ignoring errors** - handle them or propagate them
- **NO magic numbers** - use named constants
- **NO massive views** - break them into smaller components

### Required Standards:
- Use `guard let` for early returns
- Prefer `if let` over force unwrapping
- Use `@Observable` macro for view models (not ObservableObject)
- Use SwiftData `@Model` for persistence
- Use Swift Concurrency (async/await, actors) - no completion handlers
- Use structured concurrency with TaskGroups when appropriate
- Explicit access control (`private`, `internal`, `public`)
- Use extensions to organize code logically
- Keep views under 100 lines - extract subviews
- Use `#Preview` macro for SwiftUI previews

## Architecture

### Layer Separation
```
Views (SwiftUI)
    ↓
ViewModels (@Observable)
    ↓
Services (Business Logic)
    ↓
Models (SwiftData @Model)
```

### SwiftData Patterns
```swift
// Good: Use @Query for reactive data
@Query(filter: #Predicate<Stack> { !$0.isDeleted })
private var stacks: [Stack]

// Good: Use ModelContext for writes
modelContext.insert(newStack)
try modelContext.save()
```

### Service Layer Pattern
- All business logic lives in Services
- Services are actors or have actor isolation where needed for thread safety
- Views should be thin - just UI logic

## Platform Considerations

### iOS/iPadOS
- Use TabView for main navigation
- Support Dynamic Type
- Handle safe areas properly
- Support both orientations

### macOS
- Use NavigationSplitView for sidebar navigation
- Support keyboard shortcuts (⌘N, ⌘S, etc.)
- Respect system appearance

### Shared
- Use `#if os(iOS)` / `#if os(macOS)` sparingly
- Prefer adaptive layouts that work everywhere
- Test on all platforms before PR

## Error Handling

```swift
// Good: Propagate errors
func loadData() async throws -> [Stack] {
    try await stackService.fetchAll()
}

// Good: Handle at appropriate level
do {
    let stacks = try await loadData()
} catch {
    logger.error("Failed to load stacks: \(error)")
    showError(error)
}
```

## Testing Requirements

- Unit tests for all Services
- UI tests for critical user flows
- Use Swift Testing framework (`@Test`, `#expect`)
- Mock dependencies using protocols
- Test on both iOS and macOS

## Git and Commit Guidelines

- Create feature branches off main (`feat/`, `fix/`, `refactor/`)
- Keep commits atomic and well-described
- Squash before merging if many small commits
- Never force push to main

## Communication Protocol

### Progress Updates:
```
✓ Implemented StackService with full test coverage
✓ Added HomeView with drag-to-reorder
✗ Found issue with sync - investigating
```

### Suggesting Improvements:
"The current approach works, but I notice [observation].
Would you like me to [specific improvement]?"

## Project Management

- **Issue Tracker**: Linear (project key: DEQ)
- **Always use Linear MCP** to fetch issue details when given a ticket ID (e.g., DEQ-10)
- Issues follow format: DEQ-XX

## Related Projects

- **stacks-sync** - Backend sync service (https://stacks-sync.fly.dev)
- **stacks** - Legacy React Native app (deprecated)
