---
active: true
iteration: 1
max_iterations: 100
completion_promise: "COMPLETE"
started_at: "2026-01-18T00:39:18Z"
---


  Task: Merge All Open PRs

  Review and merge all open pull requests one by one, addressing CI failures and code review feedback systematically until all PRs are merged.

  Context:
  - Current open PRs: #159 (sync reconnection), #151 (tag sync race condition)
  - PR #151: All checks passing, ready to merge
  - PR #159: Waiting for unit tests to complete

  Constraints:
  - MUST address ALL CI check failures before merging
  - MUST address ALL feedback from Claude Code review before merging
  - NEVER merge if Claude Code says merge once feedback is addressed until feedback is actually addressed
  - NEVER merge with pending or in-progress CI checks
  - MUST wait for all checks to complete using gh pr checks --watch
  - DO NOT use code blocks with backticks in any prompts or state files

  State Management:

  Maintain state in .claude/ralph-state.json with this structure:
  - phase (number): current phase 0-2
  - iteration (number): current iteration count
  - currentPR (number or null): PR number being processed
  - openPRs (array): list of all open PR numbers
  - mergedPRs (array): list of merged PR numbers
  - blocked (array): current blockers
  - lastAction (string): last action taken
  - ciHistory (array): history of CI results
  - feedbackAddressed (array): feedback that has been addressed
  - feedbackPending (array): feedback still pending

  On every iteration:
  1. Read .claude/ralph-state.json if it exists and increment iteration
  2. If doesnt exist: create it and ensure .claude/ is in .gitignore
  3. Update state after each significant action

  On completion:
  - Delete .claude/ralph-state.json

  Phase 0: Setup (First Iteration Only)

  1. Check if .gitignore contains .claude/ line
  2. If not: append .claude/ line and commit with message chore: gitignore .claude directory
  3. Create .claude/ralph-state.json with initial state
  4. Fetch all open PRs: gh pr list --state open --json number,title,url
  5. Store PR numbers in openPRs array
  6. Update state: phase to 1
  7. Continue to Phase 1

  Phase 1: Process Each PR

  For each PR in openPRs that is not in mergedPRs:

  1. Update state: currentPR to the PR number
  2. Checkout PR branch: gh pr checkout {number}
  3. WAIT for CI completion: gh pr checks --watch (this blocks until all checks complete)
  4. Verify all checks complete: gh pr checks
  5. Record CI results in ciHistory with timestamp

  If ANY CI Check Failed:
  1. Get failure details: gh run view --log
  2. Update blocked array with failure type and details
  3. Fix the issue based on error messages
  4. Commit fix with descriptive message
  5. Push: git push
  6. Update state: move item from blocked to completed, record action in lastAction
  7. GOTO step 3 (wait for CI again)

  If ALL CI Checks Pass:
  1. Fetch Claude Code review: gh pr view {number} --json reviews
  2. Parse for any unaddressed feedback
  3. If feedback requires changes:
     - Add items to feedbackPending
     - Address each item with code changes
     - Commit changes with descriptive message
     - Push: git push
     - Move items from feedbackPending to feedbackAddressed
     - Update lastAction
     - GOTO step 3 (wait for CI again)
  4. If no feedback or all feedback addressed:
     - Final verification: gh pr checks shows ALL pass
     - Merge: gh pr merge {number} --squash --auto
     - Add PR number to mergedPRs array
     - Update lastAction with merge confirmation
     - Continue to next PR in openPRs

  Phase 2: Completion Check

  After processing all PRs:
  1. Verify mergedPRs length equals openPRs length
  2. If yes: delete .claude/ralph-state.json
  3. Output summary of all merged PRs
  4. Output completion promise

  Exit Conditions:

  Output COMPLETE promise ONLY when ALL are true:
  - All open PRs have been merged
  - No PRs remain in blocked state
  - State file has been deleted
  - mergedPRs array contains all PR numbers from openPRs array

  Do NOT Exit If:
  - Any PR has pending or in_progress CI checks
  - Any PR has failing CI checks
  - Any PR has unaddressed Claude Code feedback requiring changes
  - mergedPRs length does not equal openPRs length
  - Any items remain in blocked array

  Stuck Handling:

  If iteration reaches 85:
  - Document all current blockers in state
  - List all attempted fixes from completed array
  - Add detailed comment to problematic PR explaining situation
  - Suggest manual intervention steps
  - Delete .claude/ralph-state.json
  - Output COMPLETE promise with BLOCKED status in final message
  
