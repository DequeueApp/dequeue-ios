# Project Instructions: Dequeue

## Overview

Dequeue is an offline-first personal task management system built around event streams, preserved context, and near–real-time cross-device sync.

Dequeue is not a to-do list and not project management software.
It models work as evolving context: tasks are created, edited, blocked, resumed, and reordered over time without losing intent.

-----

## Core Constraints (Authoritative)

- Exactly one active Stack at a time
- Exactly one active Task within the active Stack
- Other stacks and tasks may exist, but are inactive

This constraint is intentional and central to Dequeue's focus model.

-----

## Stack & Task Model (Clarified)

- A Stack is not strictly LIFO
- Tasks within a stack:
  - Are not required to be completed in order
  - May be activated in any order
  - Preserve rich metadata:
    - Creation time
    - Last-active time
    - Blocked / waiting state
    - Optional parent relationships

This design emerged from real usage: strict linear stacks were frustrating and unrealistic.

Dequeue optimizes for flexible navigation with preserved history, not rigid abstractions.

-----

## Event-First Architecture (Key Principle)

Dequeue is event-first by design, not just event-sourced internally.

- Every change is expressed as an event
- Events are:
  - Sent to the backend
  - Persisted with precise timestamps
  - Replayed to derive state
- Clients do not mutate state directly
  - They emit events
  - Then rehydrate projections from the same pipeline

There is a single canonical source of truth: the event stream.

-----

## Sync Model

- Offline-first by default
- Cloud sync is built-in for v1
- Conflict resolution is Last Write Wins (LWW)

**Behavior:**

- Events are queued locally while offline
- On reconnect:
  - Events sync to the backend
  - Backend orders by timestamp
  - State is re-derived
  - Events are pushed to other devices (near real-time)
  - All clients converge deterministically

CRDT-style merging is intentionally avoided in favor of:

- Simplicity
- Predictability
- Debuggability

-----

## Reminders

- Reminders are first-class entities
- Can attach to:
  - Tasks
  - Stacks
- Support:
  - One-time reminders
  - Snoozing
  - (Future) recurrence
- Trigger local notifications with actions
- All reminder actions emit events

-----

## AI-Native Assumptions

Dequeue assumes:

- Tasks may be delegated to AI agents
- AI work is asynchronous
- Results return later
- Context must survive that delay

AI may:

- Complete tasks
- Propose new tasks
- Reorder tasks
- Attach reminders

Dequeue tracks intent and responsibility, not just completion.

### Example (Condensed)

```
Active Stack: "Prepare board memo"

Tasks:
- Draft narrative (active)
- Pull metrics (blocked)
- Review last memo (pending)
```

Work continues despite blockers.
Order is flexible.
Context is preserved.

-----

## Technical Stack (Current)

- **Client:** Swift + SwiftUI
- **Backend:** Go
- **API:** REST
- **Transport:** Event delivery + real-time push (e.g., WebSockets)
- **IDs:** CUIDs
- **Architecture:**
  - Event-first
  - Event-sourced
  - Offline-first
  - Last-write-wins sync

-----

## Assistant Expectations

When assisting with Dequeue:

- Treat the user as an expert
- Do not assume strict stack semantics
- Respect:
  - One active stack
  - One active task
- Think in events first, projections second
- Assume:
  - Offline operation
  - Near–real-time cross-device sync
- Prefer simple, explainable primitives
- Optimize for real human cognition, not theoretical purity

-----

## Naming

- **Product name:** Dequeue
- No acronyms
- Naming should be:
  - Short
  - Non-whimsical
  - Easy to pronounce
  - Abstract rather than descriptive
