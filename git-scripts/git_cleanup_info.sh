#!/bin/bash

# Check if in a Git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "Not in a Git repository"
  exit 1
fi

# Set colors if output is a terminal
if [[ -t 1 ]]; then
  COLOR_TAG="\033[1;34m"  # Blue
  COLOR_BRANCH="\033[1;32m"  # Green
  COLOR_STASH="\033[1;33m"  # Yellow
  COLOR_RESET="\033[0m"
else
  COLOR_TAG=""
  COLOR_BRANCH=""
  COLOR_STASH=""
  COLOR_RESET=""
fi

# Print repository path
repo_path=$(git rev-parse --show-toplevel)
echo "Repository: $repo_path"
echo ""

# Tags section
echo -e "${COLOR_TAG}===== Tags (Local Only) =====${COLOR_RESET}"
# Fetch remote tags for comparison (quietly)
git fetch --tags --quiet 2>/dev/null
# Get all local tags
local_tags=$(git tag)
if [ -n "$local_tags" ]; then
  # Get all remote tags (stripping refs/remotes/origin/ prefix)
  remote_tags=$(git ls-remote --tags origin | awk '{print $2}' | sed 's/refs\/tags\///' | sed 's/\^{}$//')
  # Process each local tag
  echo "$local_tags" | while IFS= read -r tag; do
    # Check if tag exists in remote_tags
    if ! echo "$remote_tags" | grep -Fx "$tag" > /dev/null; then
      # Tag is local-only
      echo "Tag: $tag"
      # Get tag date and commit
      date=$(git for-each-ref --format='%(if)%(taggerdate)%(then)%(taggerdate:iso8601)%(else)%(*authordate:iso8601)%(end)' "refs/tags/$tag")
      commit=$(git for-each-ref --format='%(objectname)' "refs/tags/$tag")
      echo "  Date: $date"
      echo "  Commit: $commit"
      commit_msg=$(git log -1 --format=%s "$commit")
      echo "  Commit Message: $commit_msg"
      echo "  Files Changed:"
      git show --name-only --format= "$commit" | sed 's/^/    - /'
      echo "  Delete Command: git tag -d $tag"
      echo ""
    fi
  done
else
  echo "No local tags found."
  echo ""
fi

# Branches section (unchanged)
echo -e "${COLOR_BRANCH}===== Branches =====${COLOR_RESET}"
git branch -vv | while read -r line; do
  branch=$(echo "$line" | sed 's/^\* //' | awk '{print $1}')
  if echo "$line" | grep -q '\[.*: ahead'; then
    status="ahead"
  elif ! echo "$line" | grep -q '\['; then
    status="no upstream"
  else
    continue
  fi
  echo "Branch: $branch"
  last_commit_date=$(git log -1 --format=%ai "$branch")
  echo "  Last Commit Date: $last_commit_date"
  commit_msg=$(git log -1 --format=%s "$branch")
  echo "  Commit Message: $commit_msg"
  echo "  Files Changed:"
  git show --name-only --format= "$branch" | sed 's/^/    - /'
  echo "  Status: $status"
  echo "  Delete Command: git branch -d $branch"
  echo ""
done

# Stashes section (unchanged)
echo -e "${COLOR_STASH}===== Stashes =====${COLOR_RESET}"
git stash list --format="%gd%09%ai%09%gs" | while IFS=$'\t' read -r stash_ref date subject; do
  if [ -n "$stash_ref" ]; then
    echo "Stash: $stash_ref"
    echo "  Date: $date"
    branch=$(echo "$subject" | sed 's/^WIP on \([^:]*\):.*/\1/')
    echo "  Branch: $branch"
    echo "  Changes:"
    git stash show --name-only "$stash_ref" | sed 's/^/    - /'
    echo "  Drop Command: git stash drop $stash_ref"
    echo ""
  fi
done