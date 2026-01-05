# Development Partnership

We're building a production-quality native iOS/iPadOS/macOS app together. Your role is to create maintainable, efficient Swift code while catching potential issues early.

> **See also:** [PROJECT.md](PROJECT.md) for product context, architecture principles, and domain model.

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

## Git Workflow

### Branching Strategy
- We follow **trunk-based development** with short-lived feature branches
- Branch names MUST include the Linear issue ID
- Format: `<issue-id>/<short-description>` (e.g., `DEQ-123/add-user-auth`)
- The issue ID should be lowercase in branch names

### Updating Feature Branches
- **NEVER use `git merge main`** to update feature branches
- Always use `git rebase origin/main` to update a feature branch with changes from main
- After rebasing, use `git push --force-with-lease` (never bare `--force`)

### Commits
- Keep commits atomic and well-described
- Squash before merging if many small commits
- Never force push to main

## Pull Requests

- Keep PRs small and focused
- Always rebase onto main before marking PR ready for review
- Link PRs to their Linear issue

## CI Checks

### Act on Failures Immediately - Don't Wait!
**NEVER wait for all CI checks to complete before acting on failures.**

If there are 7 CI checks running and 1 fails while others are still in progress:
- **Start fixing the failed check immediately** - don't sleep/poll waiting for the other 6
- You already have actionable information - use it
- Waiting for all checks to finish when you could be fixing known failures is wasteful

### Iterative CI Response
- Monitor checks as they complete, not just when all finish
- Act on the **first failure** rather than waiting for complete results
- If multiple checks fail, you can address them in parallel if they're independent
- Only wait for all checks when everything is passing and you need final confirmation

### Why This Matters
- CI checks have varying durations - some take seconds, others take minutes
- A fast-failing linter check shouldn't wait for a slow integration test
- Every minute spent sleeping on known failures is wasted time

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

## Linear Integration & Workflow

- **Issue Tracker**: Linear (project key: DEQ)
- Issues follow format: DEQ-XX
- **Always check for Linear MCP availability first** - try to use it to fetch issue details when given a ticket ID (e.g., DEQ-10)

### Every Task Needs a Linear Issue
- **Before starting ANY work**, check if there is a Linear issue for it
- If no issue exists and Linear MCP is available, create one first using the appropriate team and project
- Prefer not to start coding without a Linear issue to track the work

### When Linear MCP is Unavailable
If the Linear MCP server is not available (e.g., in Claude Code Cloud or other restricted environments):
- **You can still proceed with work** - don't let unavailability block progress
- Note in your response that you couldn't access Linear and recommend the user create/update the issue
- Use descriptive branch names even without an issue ID: `feature/<description>` or `fix/<description>`
- Document decisions and context in commit messages and PR descriptions instead
- When Linear becomes available again, update the relevant issue with what was done

### Linear as System of Record
- Write the implementation plan to the Linear issue description or as a comment before starting work
- Update the issue with important decisions, trade-offs, and context as you go
- When work is complete, ensure the issue documents what was done and why
- Link related PRs to the Linear issue

### Subtasks and Related Issues
- If a task is complex, break it into subtasks in Linear
- If you discover related work that needs to be done, create separate Linear issues for it
- Link related issues together in Linear

### Workflow Summary
1. Receive task/request
2. Check for Linear MCP availability
3. If available: find or create Linear issue, write implementation plan to the issue
4. Create branch using issue ID: `git checkout -b <issue-id>/description` (or `feature/description` if no issue)
5. Do the work, updating Linear with key decisions (if available)
6. Rebase onto main before PR
7. Ensure Linear issue is updated with final context (or recommend user updates it)

## Related Projects

- **stacks-sync** - Backend sync service (https://stacks-sync.fly.dev)
- **stacks** - Legacy React Native app (deprecated)
