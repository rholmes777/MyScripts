#!/bin/bash
# git_cleanup_info.sh
# Script to identify all potential changes in local Git repository workspaces
# that are NOT pushed to any remotes (both upstream and origin)

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a remote exists
remote_exists() {
    git remote | grep -q "^$1$"
}

# Function to display header with green color
display_header() {
    GREEN='\033[0;32m'
    NC='\033[0m' # No Color
    echo -e "\n${GREEN}===== $1 =====${NC}\n"
}

# Check if script is run inside a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not a git repository"
    exit 1
fi

# Check if git is installed
if ! command_exists git; then
    echo "Error: git is not installed"
    exit 1
fi

# Get repository name
repo_name=$(basename "$(git rev-parse --show-toplevel)")
echo "Repository: $repo_name"
echo "Date: $(date)"
echo

# Get remote information
remotes=()
if remote_exists "upstream"; then
    remotes+=("upstream")
fi
if remote_exists "origin"; then
    remotes+=("origin")
fi

if [ ${#remotes[@]} -eq 0 ]; then
    echo "Error: Neither 'upstream' nor 'origin' remotes found"
    exit 1
fi

echo "Checking against remotes: ${remotes[*]}"

# Fetch all remotes to ensure we have the latest data
for remote in "${remotes[@]}"; do
    echo "Fetching from $remote..."
    git fetch "$remote" --tags --prune >/dev/null 2>&1
done

# Function to check if a branch exists in any remote
branch_in_remotes() {
    local branch=$1
    for remote in "${remotes[@]}"; do
        if git branch -r | grep -q "$remote/$branch$"; then
            return 0
        fi
    done
    return 1
}

# Function to check if a tag exists in any remote
tag_in_remotes() {
    local tag=$1
    for remote in "${remotes[@]}"; do
        if git ls-remote --tags "$remote" | grep -q "refs/tags/$tag$"; then
            return 0
        fi
    done
    return 1
}

# Check local branches that don't exist in remotes
display_header "LOCAL BRANCHES NOT IN REMOTES"
found_unpushed_branches=false

for branch in $(git branch --format='%(refname:short)'); do
    if ! branch_in_remotes "$branch"; then
        found_unpushed_branches=true
        commit_sha=$(git rev-parse "$branch")
        author=$(git show -s --format="%an <%ae>" "$branch")
        echo "Branch: $branch"
        echo "  Commit: $commit_sha"
        echo "  Author: $author"
        echo "  Last commit message: $(git log -1 --pretty=%B "$branch" | head -1)"
        echo "  Last commit date: $(git log -1 --pretty=%cd --date=local "$branch")"
        echo "  Show command: git show $branch"
        echo "  Delete command: git branch -D $branch"
        echo
    fi
done

if [ "$found_unpushed_branches" = false ]; then
    echo "No local branches found that aren't in remotes."
    echo
fi

# Check for stashes
display_header "STASHES"
stash_list=$(git stash list)
if [ -z "$stash_list" ]; then
    echo "No stashes found."
    echo
else
    echo "$stash_list" | while read -r stash_line; do
        stash_id=$(echo "$stash_line" | cut -d: -f1)
        stash_sha=$(git rev-parse "$stash_id")
        stash_message=$(echo "$stash_line" | cut -d: -f2-)
        author=$(git show -s --format="%an <%ae>" "$stash_id")
        echo "Stash: $stash_id $stash_message"
        echo "  Commit: $stash_sha"
        echo "  Author: $author"
        echo "  Date: $(git show -s --format=%cd --date=local "$stash_id")"
        echo "  Show command: git stash show -p $stash_id"
        echo "  Delete command: git stash drop $stash_id"
        echo
    done
fi

# Check local tags that don't exist in remotes
display_header "LOCAL TAGS NOT IN REMOTES"
found_unpushed_tags=false

for tag in $(git tag); do
    if ! tag_in_remotes "$tag"; then
        found_unpushed_tags=true
        tag_sha=$(git rev-parse "$tag")
        author=$(git show -s --format="%an <%ae>" "$tag")
        echo "Tag: $tag"
        echo "  Commit: $tag_sha"
        echo "  Author: $author"
        echo "  Tag message: $(git tag -l -n1 "$tag" | sed 's/^[^ ]* *//')"
        echo "  Tag date: $(git log -1 --pretty=%cd --date=local "$tag^{commit}")"
        echo "  Show command: git show $tag"
        echo "  Delete command: git tag -d $tag"
        echo
    fi
done

if [ "$found_unpushed_tags" = false ]; then
    echo "No local tags found that aren't in remotes."
    echo
fi

# Check for uncommitted changes
display_header "UNCOMMITTED CHANGES"
if git diff --quiet; then
    if git diff --cached --quiet; then
        echo "No uncommitted changes."
    else
        echo "Changes staged for commit:"
        git diff --cached --stat
    fi
else
    echo "Unstaged changes:"
    git diff --stat
    if ! git diff --cached --quiet; then
        echo -e "\nStaged changes:"
        git diff --cached --stat
    fi
fi

# Check for untracked files
display_header "UNTRACKED FILES"
untracked_files=$(git ls-files --others --exclude-standard)
if [ -z "$untracked_files" ]; then
    echo "No untracked files."
else
    echo "$untracked_files"
fi

echo -e "\nDone."