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
  # Get all remote tags
  remote_tags=$(git tag -l -r origin)
  # Process each local tag
  echo "$local_tags" | while IFS= read -r tag; do
    # Check if tag exists in remote_tags
    if ! echo "$remote_tags" | grep -Fx "$tag" >/dev/null; then
      # Tag is local-only
      echo "Tag: $tag"
      # Get tag date (commit's author date)
      date=$(git log -1 --format=%ai "$(git rev-parse "$tag")")
      commit=$(git rev-parse "$tag")
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

# Branches section
echo -e "${COLOR_BRANCH}===== Branches =====${COLOR_RESET}"
found_branches=0
git branch -vv | while read -r line; do
  branch=$(echo "$line" | sed 's/^\* //' | awk '{print $1}')
  if echo "$line" | grep -q '\[.*: ahead'; then
    status="ahead"
  elif ! echo "$line" | grep -q '\['; then
    status="no upstream"
  else
    continue
  fi
  found_branches=1
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
if [ "$found_branches" -eq 0 ]; then
  echo "No local branches found needing cleanup."
  echo ""
fi

# Stashes section
echo -e "${COLOR_STASH}===== Stashes =====${COLOR_RESET}"
found_stashes=0
git stash list | while read -r stash_line; do
  if [ -n "$stash_line" ]; then
    found_stashes=1
    stash_ref=$(echo "$stash_line" | cut -d: -f1)
    # Extract date using git show for reliability
    date=$(git show -s --format=%ai "$stash_ref")
    subject=$(echo "$stash_line" | cut -d: -f2- | sed 's/^[ \t]*//')
    # Handle both "WIP on <branch>" and "On <branch>" formats
    branch=$(echo "$subject" | sed -E 's/^(WIP on|On) ([^:]+):?.*/\2/' | sed 's/^[ \t]*//')
    echo "Stash: $stash_ref"
    echo "  Date: $date"
    echo "  Branch: $branch"
    echo "  Changes:"
    git stash show --name-only "$stash_ref" | sed 's/^/    - /'
    echo "  Drop Command: git stash drop $stash_ref"
    echo ""
  fi
done
if [ "$found_stashes" -eq 0 ]; then
  echo "No stashes found."
  echo ""
fi