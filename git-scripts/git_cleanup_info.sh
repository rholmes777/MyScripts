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
echo -e "${COLOR_TAG}===== Tags =====${COLOR_RESET}"
git for-each-ref --format='%(refname:short)%09%(if)%(taggerdate)%(then)%(taggerdate:iso8601)%(else)%(*authordate:iso8601)%(end)%09%(objectname)' refs/tags | while IFS=$'\t' read -r tag date commit; do
  if [ -n "$tag" ]; then
    echo "Tag: $tag"
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

# Branches section
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

# Stashes section
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
