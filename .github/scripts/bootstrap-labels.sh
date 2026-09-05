#!/usr/bin/env bash
# Create every label the agent control plane triggers on.
#
# NEW IN THIS REPO -- the source repo has no equivalent, and documents the gap
# this fills: the eight `agent:{role}:{vendor}` labels "are not created by any
# workflow; must already exist", and have no `ensure_label` guard anywhere in
# `.github/`. In a repository that already had them that is a footnote about
# deletion. In a fresh one it means the entire control plane is inert on
# arrival -- every trigger is keyed on a label name that does not exist, so
# nothing fires and nothing reports why.
#
# The rest are bootstrapped lazily by whichever workflow's `ensure_label`
# guard runs first. Creating them up front costs nothing and makes the
# repository's Labels page readable before the first Issue is filed.
#
# Idempotent: an existing label is updated to the color/description below
# rather than erroring. Safe to re-run after editing this file.
#
# Usage: .github/scripts/bootstrap-labels.sh [owner/repo]
# Requires `gh` authenticated with repo scope.

set -euo pipefail

repo="${1:-}"
if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

echo "Bootstrapping labels on $repo"

# name|color|description
LABELS=$(cat <<'LABELS'
agent:planner:copilot|1D76DB|Route planning for this Issue to the Copilot planner
agent:planner:claude|1D76DB|Route planning for this Issue to the Claude planner
agent:implementer:copilot|1D76DB|Route implementation to the Copilot implementer
agent:implementer:claude|1D76DB|Route implementation to the Claude implementer
agent:reviewer:copilot|1D76DB|Route review to the Copilot reviewer
agent:reviewer:claude|1D76DB|Route review to the Claude reviewer
agent:fixer:copilot|1D76DB|Route the fix cycle to the Copilot fixer
agent:fixer:claude|1D76DB|Route the fix cycle to the Claude fixer
plan|0E8A16|Intake Issue awaiting decomposition into Implementation Tasks
planned|0E8A16|Intake Issue that has been decomposed
implementation|1D76DB|Implementation Task Issue, ready for an implementer
machine|70A8BD|Work an agent session can complete unattended
human-credentials|D4C5F9|Requires credentials or console access an agent does not have
blocker|B23F00|This Issue blocks another; drives the native dependency relationship
review:pass|0E8A16|Review verdict: accepted
review:fix|D93F0B|Review verdict: bounded correction required on the same branch
review:planning-failure|B60205|Review verdict: the Issue itself was wrong, not the code
review:design-ambiguity|FBCA04|Review verdict: needs a human design decision before proceeding
dashboard|5319E7|The control-plane dashboard Issue
dashboard:update|5319E7|Request a dashboard re-render
LABELS
)

created=0
updated=0

while IFS='|' read -r name color description; do
  [ -n "$name" ] || continue

  if gh label create "$name" \
       --repo "$repo" \
       --color "$color" \
       --description "$description" >/dev/null 2>&1; then
    echo "  created  $name"
    created=$((created + 1))
  else
    # Already exists: bring color and description back in sync. The source
    # repo records `plan` drifting out of sync with its own ensure_label call
    # at some point, precisely because nothing re-asserted it.
    gh label edit "$name" \
      --repo "$repo" \
      --color "$color" \
      --description "$description" >/dev/null
    echo "  updated  $name"
    updated=$((updated + 1))
  fi
done <<< "$LABELS"

echo "Done: $created created, $updated updated."
echo
echo "Note: the eight agent:{role}:{vendor} labels have no ensure_label guard"
echo "in any workflow. If one is deleted, nothing recreates it and the trigger"
echo "keyed on it silently stops firing. Re-run this script to restore them."
