# Onboarding & First-Run Experience - PRD

**Feature:** User Onboarding  
**Author:** Ada (Dequeue Engineer)  
**Date:** 2026-02-03  
**Status:** Draft  
**Related:** ROADMAP.md Section 11

## Problem Statement

Dequeue's "one active Stack, one active task" model is fundamentally different from typical todo apps. New users launching the app for the first time will be confused by:

- **Why can't I work on multiple things at once?** (They're used to checking off tasks across multiple projects)
- **What does "active" mean?** (Is it just "selected" or something more meaningful?)
- **Where did my completed stacks go?** (Hidden by default for focus)
- **Why is this app different from Things/Todoist?** (Need to understand the value prop)

**Without explanation, users will:**
1. Try to use Dequeue like their old app
2. Feel constrained by the "one active" model
3. Not understand the focus/productivity benefits
4. Abandon the app within 24 hours

**Industry data:**
- 25% of users abandon apps after first use ([source](https://www.localytics.com/))
- Good onboarding increases retention by 50%+ ([source](https://www.apptentive.com/))
- Users decide to keep/delete apps within 3 days

**We have ONE shot at a first impression.** Nail onboarding or lose the user forever.

## Solution

A brief, interactive onboarding flow that:
1. Explains Dequeue's unique model
2. Gets users to their first "aha moment" quickly
3. Teaches through doing (create real data, not sample data)
4. Respects power users (skippable, not shown on subsequent devices)

**Key Principles:**
1. **Fast**: 60-90 seconds total
2. **Interactive**: User creates real Stacks/Tasks, not passive reading
3. **Clear value prop**: Focus on benefits, not features
4. **Respectful**: Easy to skip, never shown again if user has data
5. **Beautiful**: First-class design, animations, delight

## User Flow

### Entry Point

**When to show onboarding:**
- ✅ First launch after install (no local data)
- ✅ User explicitly taps "Show Onboarding" in Settings
- ❌ NOT on subsequent devices if user already has Stacks (check after auth)
- ❌ NOT on app updates (only fresh installs)

### Flow Overview (5 Screens)

```
Welcome → Stacks Concept → Active Focus → Create First Stack → You're Ready
 (15s)      (15s)            (15s)           (30s)                (15s)
```

**Total time: ~90 seconds**

---

### Screen 1: Welcome (15 seconds)

**Visual:**
- App icon (large, centered)
- "Welcome to Dequeue"
- Tagline: "Focus on one thing at a time"

**Content:**
```
Welcome to Dequeue

The task manager that helps you focus
by working on one thing at a time.

Let's get you set up →
```

**Actions:**
- **Primary button**: "Get Started" (continue to Screen 2)
- **Text link**: "Skip" (dimmed, bottom-left) → Goes to empty app state

**Design:**
- Clean, minimal
- Large, friendly typography
- Subtle animation on app icon (gentle bounce on appear)

---

### Screen 2: The Stack Concept (15 seconds)

**Visual:**
- Illustration: A Stack with 3-4 tasks stacked inside
- Animated: Tasks slide into the Stack

**Content:**
```
Everything lives in Stacks

Think of Stacks as projects or contexts:
• Work projects
• Personal errands
• Side hustles

Each Stack contains your Tasks.
```

**Actions:**
- **Primary button**: "Next"
- **Progress dots**: ● ○ ○ ○ ○

**Design:**
- Visual metaphor: literal stack of tasks
- Soft colors, not overwhelming
- Animation: Tasks slide in from right, settle into Stack

---

### Screen 3: One Active Stack (15 seconds)

**Visual:**
- Two Stacks shown side by side
- One has a ⭐ (active), other is dimmed
- Animated: Active Stack glows slightly

**Content:**
```
You work on one Stack at a time

The Active Stack (⭐) is what you're
focused on right now.

This keeps you honest about where
your attention is actually going.
```

**Actions:**
- **Primary button**: "Got it"
- **Progress dots**: ○ ● ○ ○ ○

**Design:**
- Clear visual distinction between active (bright) and inactive (dimmed)
- Animation: Star pulses gently

---

### Screen 4: Create Your First Stack (30 seconds)

**Visual:**
- Text field for Stack name (focused)
- Suggested prompts below: "Work", "Personal", "Side Project"

**Content:**
```
Create your first Stack

What are you working on right now?

[Text field: "Enter stack name..."]

Suggestions:
[Work]  [Personal]  [Side Project]
```

**Interaction:**
- User types Stack name OR taps a suggestion chip
- As they type, "Create & Continue" button becomes enabled
- Once created, brief success animation (checkmark, confetti burst)
- Automatically activated as the Active Stack (⭐)

**Actions:**
- **Primary button**: "Create & Continue" (enabled once name entered)
- **Progress dots**: ○ ○ ● ○ ○

**Design:**
- Focus immediately in text field (keyboard auto-appears on iOS)
- Suggestion chips: iOS standard, tappable
- Success animation: Quick burst of confetti particles from button

---

### Screen 5: You're Ready! (15 seconds)

**Visual:**
- Preview of home screen with their newly created Stack
- Callouts pointing to key UI elements

**Content:**
```
You're all set!

Here's what to know:

[⭐ icon] → Your Active Stack
[+ icon] → Add tasks to this Stack
[List icon] → See all your Stacks

Tap your Stack to get started.
```

**Actions:**
- **Primary button**: "Start Using Dequeue"
- **Progress dots**: ○ ○ ○ ○ ●

**Design:**
- Feels like a bridge to the real app
- Callouts: Subtle arrows + labels
- Button: Confident, inviting

---

### Optional: Add a Task (Post-Onboarding)

After onboarding completes, immediately prompt user to add their first task:

**Sheet/Modal:**
```
Let's add your first task

What do you need to do in [Stack Name]?

[Text field: "Enter task..."]

[Add Task]  [Skip]
```

**Why:**
- Gets user to a complete workflow: Stack created → Task added → Ready to work
- Empty Stack feels incomplete
- Increases likelihood of returning to app

**Skip handling:**
- If skipped, that's fine - user can add tasks later
- Don't force it if they're exploring

---

## Empty State (First Launch, Onboarding Skipped)

If user skips onboarding or deletes all Stacks:

**Visual:**
- Centered illustration (person at desk, lightbulb, something friendly)
- Helpful text
- Clear CTA

**Content:**
```
Nothing here yet

Stacks are how you organize your work.
Each Stack contains tasks for a project or context.

Create your first Stack to get started.

[Create Your First Stack]
```

**Design:**
- Not scary or punishing
- Inviting and helpful
- Echoes onboarding messaging

---

## Multi-Device Behavior

**Problem:** User installs on iPhone, completes onboarding. Later installs on iPad. Should they see onboarding again?

**Answer:** No.

**Implementation:**
1. After auth/sync, check if user has existing Stacks in backend
2. If `eventCount > 0`, skip onboarding (they've used the app before)
3. Only show onboarding on truly first launch (no data anywhere)

**Edge case:** User creates account on Device A, never creates a Stack, installs on Device B.
- Device B will show onboarding (eventCount == 0)
- This is correct - they haven't actually used the app yet

---

## Technical Design

### Onboarding State Management

**UserDefaults key:**
```swift
let hasCompletedOnboarding = "hasCompletedOnboarding"
```

**Check on launch:**
```swift
@main
struct DequeueApp: App {
    @State private var showOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            if showOnboarding {
                OnboardingView(onComplete: {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    showOnboarding = false
                })
            } else {
                MainTabView()
            }
        }
        .onAppear {
            checkIfShouldShowOnboarding()
        }
    }
    
    func checkIfShouldShowOnboarding() {
        // Check UserDefaults
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding = false
            return
        }
        
        // Check if user has any Stacks (synced from other device)
        let modelContext = ModelContext(...)
        let stackCount = (try? modelContext.fetchCount(FetchDescriptor<Stack>())) ?? 0
        
        if stackCount > 0 {
            // User has data from another device, skip onboarding
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            showOnboarding = false
        } else {
            // First launch, no data
            showOnboarding = true
        }
    }
}
```

### Onboarding Views (SwiftUI)

**OnboardingView (Container):**
```swift
struct OnboardingView: View {
    @State private var currentPage = 0
    let onComplete: () -> Void
    
    var body: some View {
        TabView(selection: $currentPage) {
            WelcomeView(onNext: { currentPage = 1 })
                .tag(0)
            
            StackConceptView(onNext: { currentPage = 2 })
                .tag(1)
            
            ActiveFocusView(onNext: { currentPage = 3 })
                .tag(2)
            
            CreateFirstStackView(onNext: { currentPage = 4 })
                .tag(3)
            
            AllSetView(onComplete: onComplete)
                .tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}
```

**Individual Page Example:**
```swift
struct WelcomeView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image("AppIconLarge")
                .resizable()
                .frame(width: 120, height: 120)
                .cornerRadius(27)
                .shadow(radius: 10)
                .onAppear {
                    // Gentle bounce animation
                }
            
            VStack(spacing: 16) {
                Text("Welcome to Dequeue")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("The task manager that helps you focus\nby working on one thing at a time.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button("Get Started", action: onNext)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            
            Button("Skip", action: { /* Handle skip */ })
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
```

### Animations

**Page transitions:**
- Use built-in `TabView` slide animation
- Smooth, iOS-native feel

**Welcome screen app icon:**
```swift
.onAppear {
    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
        // Bounce effect
    }
}
```

**Create Stack success:**
```swift
Button("Create & Continue") {
    // Create stack
    withAnimation(.easeInOut(duration: 0.3)) {
        showSuccessCheckmark = true
    }
    
    // Confetti burst
    triggerConfetti()
    
    // Delay, then continue
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        onNext()
    }
}
```

---

## Acceptance Criteria

### Functional
- [ ] Onboarding shows on first launch (no data)
- [ ] Onboarding does NOT show if user has Stacks (synced from other device)
- [ ] User can skip onboarding at any time
- [ ] Each screen has clear "Next" or "Continue" action
- [ ] Screen 4: User can create a Stack with custom name or suggestion
- [ ] Created Stack is automatically activated (⭐)
- [ ] Screen 5: Callouts point to correct UI elements
- [ ] "Start Using Dequeue" button completes onboarding and shows main app
- [ ] UserDefaults flag prevents onboarding from showing again
- [ ] "Show Onboarding" option in Settings (for returning users)

### Design
- [ ] iOS-native design (matches system conventions)
- [ ] Smooth page transitions
- [ ] Animations are delightful, not distracting
- [ ] Text is clear, friendly, and concise
- [ ] Dark mode support (all screens)
- [ ] Responsive to different screen sizes (iPhone SE to Pro Max)
- [ ] Landscape support (especially on iPad)

### Performance
- [ ] No lag during page transitions
- [ ] Text field on Screen 4 focuses immediately
- [ ] Animations run at 60fps
- [ ] Onboarding loads quickly (<500ms)

## Edge Cases

1. **User force-quits app during onboarding**: Resume where they left off (track current page)
2. **User skips onboarding, then wants to see it again**: "Show Onboarding" in Settings
3. **User creates Stack on Device A, installs on Device B**: Device B skips onboarding (has data)
4. **User enters very long Stack name**: Truncate in UI, store full name
5. **User taps "Create & Continue" without entering name**: Disable button until name entered
6. **Network unavailable during onboarding**: Works fully offline (local-first)

## Testing Strategy

### Unit Tests
```swift
@Test func onboardingShownOnFirstLaunch() {
    UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    
    let shouldShow = OnboardingManager.shouldShowOnboarding(stackCount: 0)
    #expect(shouldShow == true)
}

@Test func onboardingSkippedIfUserHasData() {
    UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    
    let shouldShow = OnboardingManager.shouldShowOnboarding(stackCount: 5)
    #expect(shouldShow == false)
}

@Test func onboardingSetsCompletionFlag() {
    let manager = OnboardingManager()
    manager.completeOnboarding()
    
    let completed = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    #expect(completed == true)
}
```

### Manual Testing
- Fresh install → Verify onboarding shows
- Skip onboarding → Verify empty state appears
- Complete onboarding → Verify flag set, not shown again
- Reinstall after having data → Verify onboarding skipped
- Test all screens for design consistency
- Test on iPhone SE (small screen) and Pro Max (large screen)
- Test in light and dark mode
- Test animations on device (not just simulator)

### A/B Testing Ideas (Post-Launch)
- Test different copy/messaging
- Test 3-screen vs 5-screen flow
- Test illustration styles
- Measure completion rate and impact on retention

## Implementation Plan

**Estimated: 1.5-2 days**

### Day 1: Core Flow (6-8 hours)
1. Create `OnboardingView` container with `TabView` (1 hour)
2. Build all 5 screen views (SwiftUI) (3 hours)
3. Implement onboarding state management (UserDefaults + check logic) (1 hour)
4. Wire up navigation between screens (1 hour)
5. Test flow end-to-end on simulator (1 hour)

### Day 2: Polish & Testing (4-6 hours)
1. Add animations (app icon bounce, confetti, page transitions) (2 hours)
2. Handle skip functionality (30 min)
3. Add "Show Onboarding" setting (30 min)
4. Dark mode and responsive design polish (1 hour)
5. Unit tests (1 hour)
6. Manual testing on devices (1 hour)
7. PR review & merge (1 hour + CI time)

**Total: 10-14 hours** (spread across 2 days)

## Dependencies

- ✅ No new dependencies
- ✅ SwiftUI built-in components sufficient
- ✅ Works fully offline (no network required)

**No blockers - ready to implement immediately.**

## Out of Scope

- Video tutorials (maybe Phase 2 if needed)
- Interactive app tour (tooltips on main UI) - separate feature
- Personalization quiz (work style, preferences) - Phase 2
- Multi-language localization (English only for MVP)

## Future Enhancements

**Phase 2:**
- A/B test different onboarding flows
- Add optional "Create a task" step (currently post-onboarding prompt)
- Contextual tips/tooltips throughout app (progressive disclosure)
- Onboarding for new features (when shipped)

**Phase 3:**
- Personalization: Ask user about work style (focus vs multitask)
- Role-based onboarding: Developer vs Designer vs Manager
- Video walkthroughs (if users need more help)

## Success Metrics

**Completion Rate:**
- % of users who complete onboarding vs skip
- Target: 80%+ complete (20% skip is acceptable)

**Retention Impact:**
- Day 1 retention: Users who complete onboarding vs skip
- Day 7 retention: Same comparison
- Target: 15-20% lift in retention for completed onboarding

**Time to Value:**
- Time from install to first Stack created
- Target: <2 minutes (90 sec onboarding + 30 sec exploration)

**User Feedback:**
- Qualitative feedback via TestFlight or support channels
- "Did onboarding help you understand Dequeue?"

---

**Next Steps:**
1. Review PRD with Victor
2. Create implementation ticket (DEQ-XXX)
3. Design team: Create illustrations/animations (if needed)
4. Implement when CI is responsive
5. Ship and monitor completion rate + retention impact

**First impressions matter.** Great onboarding turns confused visitors into loyal users. Let's nail it. 🚀
