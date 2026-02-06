#!/bin/bash
# monitor-ci.sh - Monitor CI status for open PRs
# Usage: ./scripts/monitor-ci.sh [--watch]

set -euo pipefail

REPO="DequeueApp/dequeue-ios"
WATCH_MODE=false
INTERVAL=60  # seconds between checks in watch mode

# Parse arguments
for arg in "$@"; do
    case $arg in
        --watch|-w)
            WATCH_MODE=true
            shift
            ;;
        --interval=*)
            INTERVAL="${arg#*=}"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--watch] [--interval=SECONDS]"
            echo ""
            echo "Options:"
            echo "  --watch, -w           Continuously monitor (refresh every ${INTERVAL}s)"
            echo "  --interval=SECONDS    Set watch interval (default: 60)"
            echo "  --help, -h            Show this help"
            exit 0
            ;;
    esac
done

# Function to check CI status
check_ci() {
    # Clear screen if TERM is set (skip in CI/automation environments)
    if [[ -n "${TERM:-}" ]]; then
        clear
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Dequeue iOS - CI Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Get all open PRs
    PRs=$(gh pr list --repo "$REPO" --state open --json number,title 2>/dev/null || echo "[]")
    
    if [[ "$PRs" == "[]" ]]; then
        echo "✨ No open PRs!"
        echo ""
        return
    fi
    
    # Parse PR numbers
    PR_NUMBERS=$(echo "$PRs" | jq -r '.[].number')
    
    for PR_NUM in $PR_NUMBERS; do
        # Get PR details
        PR_DATA=$(gh pr view "$PR_NUM" --repo "$REPO" --json number,title,statusCheckRollup 2>/dev/null || echo "{}")
        
        PR_TITLE=$(echo "$PR_DATA" | jq -r '.title // "Unknown"')
        
        echo "📋 PR #${PR_NUM}: ${PR_TITLE}"
        echo ""
        
        # Get status check rollup
        CHECKS=$(echo "$PR_DATA" | jq -r '.statusCheckRollup[]? | "\(.name)|\(.status)|\(.conclusion)"' 2>/dev/null || echo "")
        
        if [[ -z "$CHECKS" ]]; then
            echo "  ⚠️  No CI checks found"
            echo ""
            continue
        fi
        
        # Parse and display checks
        while IFS='|' read -r NAME STATUS CONCLUSION; do
            # Determine emoji and status text
            if [[ "$STATUS" == "COMPLETED" ]]; then
                case "$CONCLUSION" in
                    SUCCESS)
                        EMOJI="✅"
                        STATUS_TEXT="pass"
                        ;;
                    FAILURE)
                        EMOJI="❌"
                        STATUS_TEXT="FAIL"
                        ;;
                    SKIPPED)
                        EMOJI="⏭️ "
                        STATUS_TEXT="skip"
                        ;;
                    *)
                        EMOJI="❓"
                        STATUS_TEXT="$CONCLUSION"
                        ;;
                esac
            elif [[ "$STATUS" == "IN_PROGRESS" ]]; then
                EMOJI="🔄"
                STATUS_TEXT="running"
            elif [[ "$STATUS" == "PENDING" ]]; then
                EMOJI="⏳"
                STATUS_TEXT="pending"
            else
                EMOJI="❓"
                STATUS_TEXT="$STATUS"
            fi
            
            printf "  %s %-30s %s\n" "$EMOJI" "$NAME" "$STATUS_TEXT"
        done <<< "$CHECKS"
        
        echo ""
        echo "  URL: https://github.com/${REPO}/pull/${PR_NUM}"
        echo ""
        echo "────────────────────────────────────────────────────────"
        echo ""
    done
    
    if [[ "$WATCH_MODE" == true ]]; then
        echo "Refreshing in ${INTERVAL}s... (Ctrl+C to stop)"
    fi
}

# Main loop
if [[ "$WATCH_MODE" == true ]]; then
    while true; do
        check_ci
        sleep "$INTERVAL"
    done
else
    check_ci
fi
