#!/usr/bin/env bash
# Minimal port of textnow-server's resolve-stage-runtime.sh.
# Sets is_hotfix=true if the merge-group commit's first PR has:
#   - label `hotfix-fast-path`, OR
#   - branch name starting with `hotfix-` or `INC-`.

set -euo pipefail

HOTFIX_LABEL="hotfix-fast-path"

echo "Resolving hotfix flag from merge queue context..."

if [[ "${GITHUB_EVENT_NAME:-}" != "merge_group" ]]; then
  echo "Event ${GITHUB_EVENT_NAME:-unknown} is not merge_group; defaulting is_hotfix=false."
  echo "is_hotfix=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "Error: GH_TOKEN is not set" >&2
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "Error: GITHUB_REPOSITORY is not set" >&2
  exit 1
fi

owner="${GITHUB_REPOSITORY%%/*}"
repo="${GITHUB_REPOSITORY##*/}"
head_sha="$(jq -r '.merge_group.head_sha // empty' "$GITHUB_EVENT_PATH")"

if [[ -z "$head_sha" ]]; then
  head_sha="${GITHUB_SHA:-}"
fi

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

is_hotfix="false"

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

if echo "$labels" | grep -Fxq "$HOTFIX_LABEL"; then
  is_hotfix="true"
  echo "Hotfix fast-path triggered by label: ${HOTFIX_LABEL}"
elif [[ "$branch_name" =~ ^(INC[-/]|hotfix[-/]) ]]; then
  is_hotfix="true"
  echo "Hotfix fast-path triggered by branch prefix: ${branch_name}"
fi

echo "Resolved is_hotfix=${is_hotfix}"
echo "is_hotfix=${is_hotfix}" >> "$GITHUB_OUTPUT"
