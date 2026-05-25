#!/usr/bin/env bash
# Detects whether the current run is a hotfix fast-path.
# Sets is_hotfix=true if the PR (resolved from the event) has:
#   - label `hotfix-fast-path`, OR
#   - branch name starting with `hotfix-` or `INC-`.
#
# Supports two event shapes:
#   - merge_group  (real textnow-server path; reads first PR from the merge
#                   commit subject's `(#N)` suffix)
#   - pull_request (personal-repo repro path; reads the PR data directly
#                   from the event payload)

set -euo pipefail

HOTFIX_LABEL="hotfix-fast-path"
is_hotfix="false"
labels=""
branch_name=""

echo "Resolving hotfix flag (event=${GITHUB_EVENT_NAME:-unknown})..."

case "${GITHUB_EVENT_NAME:-}" in
  pull_request)
    labels="$(jq -r '.pull_request.labels[].name // empty' "$GITHUB_EVENT_PATH")"
    branch_name="$(jq -r '.pull_request.head.ref // empty' "$GITHUB_EVENT_PATH")"
    pr_number="$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")"
    echo "PR #${pr_number} labels: ${labels:-<none>}"
    echo "PR #${pr_number} branch: ${branch_name:-<unknown>}"
    ;;

  merge_group)
    if [[ -z "${GH_TOKEN:-}" ]]; then
      echo "Error: GH_TOKEN is not set" >&2
      exit 1
    fi
    owner="${GITHUB_REPOSITORY%%/*}"
    repo="${GITHUB_REPOSITORY##*/}"
    head_sha="$(jq -r '.merge_group.head_sha // empty' "$GITHUB_EVENT_PATH")"
    [[ -z "$head_sha" ]] && head_sha="${GITHUB_SHA:-}"
    if [[ -z "$head_sha" ]]; then
      echo "Error: could not determine merge-group head SHA" >&2
      exit 1
    fi
    commit_message="$(gh api "/repos/${owner}/${repo}/commits/${head_sha}" --jq '.commit.message')"
    echo "Merge-group commit message: ${commit_message}"
    first_pr_number=""
    if [[ "$commit_message" =~ \(#([0-9]+)\) ]]; then
      first_pr_number="${BASH_REMATCH[1]}"
    fi
    if [[ -z "$first_pr_number" ]]; then
      echo "No PR number found in merge-group commit message; defaulting is_hotfix=false."
      echo "is_hotfix=${is_hotfix}" >> "$GITHUB_OUTPUT"
      exit 0
    fi
    echo "Using first PR in merge group: #${first_pr_number}"
    pr_json="$(gh api "/repos/${owner}/${repo}/pulls/${first_pr_number}" --jq '{labels: [.labels[].name], branch: .head.ref}' || true)"
    labels="$(echo "$pr_json" | jq -r '.labels[]' 2>/dev/null || true)"
    branch_name="$(echo "$pr_json" | jq -r '.branch' 2>/dev/null || true)"
    echo "PR #${first_pr_number} labels: ${labels:-<none>}"
    echo "PR #${first_pr_number} branch: ${branch_name:-<unknown>}"
    ;;

  *)
    echo "Event ${GITHUB_EVENT_NAME:-unknown} is not merge_group or pull_request; defaulting is_hotfix=false."
    echo "is_hotfix=${is_hotfix}" >> "$GITHUB_OUTPUT"
    exit 0
    ;;
esac

if echo "$labels" | grep -Fxq "$HOTFIX_LABEL"; then
  is_hotfix="true"
  echo "Hotfix fast-path triggered by label: ${HOTFIX_LABEL}"
elif [[ "$branch_name" =~ ^(INC[-/]|hotfix[-/]) ]]; then
  is_hotfix="true"
  echo "Hotfix fast-path triggered by branch prefix: ${branch_name}"
fi

echo "Resolved is_hotfix=${is_hotfix}"
echo "is_hotfix=${is_hotfix}" >> "$GITHUB_OUTPUT"
