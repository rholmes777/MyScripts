# Check local tags that don't exist in remotes (if not disabled)
if [ "$NO_TAGS" = false ]; then
    display_header "LOCAL TAGS NOT IN REMOTES"
    found_unpushed_tags=false

    # Get local tags first
    local_tags=$(git tag)
    if [ -z "$local_tags" ]; then
        echo "No local tags found."
        echo
    else
        # Warning about limitations in no-fetch mode
        if [ "$NO_FETCH" = true ]; then
            echo -e "${YELLOW}Warning: Running in --no-fetch mode. Tag detection has limitations without fetching.${NC}"
            echo -e "${YELLOW}For most accurate results, run without --no-fetch option.${NC}"
            echo
        fi

        echo "Comparing local tags against remotes..."
        tag_count=0
        total_tags=$(echo "$local_tags" | wc -l)

        echo "$local_tags" | while read -r tag; do
            # Show progress every 10 tags
            tag_count=$((tag_count + 1))
            if [ $((tag_count % 10)) -eq 0 ]; then
                echo -ne "  Progress: $tag_count/$total_tags tags processed\r"
            fi

            if ! tag_in_remotes "$tag" 2>/dev/null; then
                found_unpushed_tags=true
                tag_sha=$(git rev-parse "$tag" 2>/dev/null)
                author=$(git show -s --format="%an <%ae>" "$tag" 2>/dev/null)
                echo -e "\nTag: $tag"
                echo "  Commit: $tag_sha"
                echo "  Author: $author"
                echo "  Tag message: $(git tag -l -n1 "$tag" 2>/dev/null | sed 's/^[^ ]* *//')"
                echo "  Tag date: $(git log -1 --pretty=%cd --date=local "$tag^{commit}" 2>/dev/null)"
                echo "  Show command: git show $tag"
                echo "  Delete command: git tag -d $tag"
                echo
            fi
        done

        # Final progress update
        echo -e "  Progress: $total_tags/$total_tags tags processed"

        if [ "$found_unpushed_tags" = false ]; then
            echo "No local tags found that aren't in remotes."

#!/bin/bash
# git_cleanup_info.sh
# Script to identify all potential changes in local Git repository workspaces
# that are NOT pushed to any remotes (both upstream and origin)
#
# Usage:
#   ./git_cleanup_info.sh [options]
#
# Options:
#   --no-tags     Skip checking tags (much faster for repos with many tags)
#   --no-fetch    Skip fetching from remotes (use local cache only)
#   --fast        Equivalent to --no-tags --no-fetch (fastest mode)

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

# Define other colors
YELLOW='\033[1;33m'

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

# Parse command line arguments
NO_TAGS=false
NO_FETCH=false

for arg in "$@"; do
    case $arg in
        --no-tags)
            NO_TAGS=true
            ;;
        --no-fetch)
            NO_FETCH=true
            ;;
        --fast)
            NO_TAGS=true
            NO_FETCH=true
            ;;
    esac
done

# Get repository name
repo_name=$(basename "$(git rev-parse --show-toplevel)")
echo "Repository: $repo_name"
echo "Date: $(date)"

# Show which features are enabled/disabled
if [ "$NO_FETCH" = true ]; then
    echo "Mode: No fetch (using local cache)"
fi
if [ "$NO_TAGS" = true ]; then
    echo "Mode: No tags (skipping tag processing)"
fi
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
if [ "$NO_FETCH" = false ]; then
    echo "Fetching from remotes (this might take a while for repos with many branches/tags)..."
    for remote in "${remotes[@]}"; do
        echo "  - Fetching from $remote..."
        # Use --no-tags to initially fetch without tags for performance
        git fetch "$remote" --prune >/dev/null 2>&1
    done

    # Only fetch tags if we need to check tags
    if [ "$NO_TAGS" = false ]; then
        echo "  - Fetching tags (use --no-tags option to skip for faster execution)..."
        for remote in "${remotes[@]}"; do
            git fetch "$remote" --tags >/dev/null 2>&1
        done
    fi
else
    echo "Skipping fetch (using local cache)"
fi

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
# For NO_FETCH=true mode, we use a best-effort approach with limitations
tag_in_remotes() {
    local tag=$1

    if [ "$NO_FETCH" = true ]; then
        # Create a simple approach for the no-fetch case that's reliable but limited
        # It will tend to under-report remote tags, which is safer
        # (better to show too many local-only tags than miss some)

        # For each remote, try to find evidence that the tag exists remotely
        for remote in "${remotes[@]}"; do
            # Check if the tag was ever mentioned in a fetch or push operation
            if git reflog | grep -q "fetch.*$remote.*tag $tag"; then
                return 0
            fi

            if git reflog | grep -q "push.*$remote.*tag $tag"; then
                return 0
            fi
        done

        # If we're here, we found no evidence in the reflog
        # Let's try one more approach - checking if tag points to a commit
        # that exists in a remote branch
        local tag_commit=$(git rev-list -n 1 "$tag" 2>/dev/null)

        # If we can't get the commit, something is wrong with the tag
        if [ -z "$tag_commit" ]; then
            return 1
        fi

        # Check if any remote branches contain this commit
        for remote in "${remotes[@]}"; do
            if git branch -r --contains "$tag_commit" 2>/dev/null | grep -q "^  $remote/"; then
                # This is a good indication the tag might exist remotely
                # but not guaranteed
                return 0
            fi
        done

        # If we get here, assume the tag is local-only
        return 1
    else
        # Use ls-remote to check remote tags (requires network)
        for remote in "${remotes[@]}"; do
            if git ls-remote --tags "$remote" 2>/dev/null | grep -q "refs/tags/$tag$"; then
                return 0
            fi
        done
    fi

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

# Check local tags that don't exist in remotes (if not disabled)
if [ "$NO_TAGS" = false ]; then
    display_header "LOCAL TAGS NOT IN REMOTES"
    found_unpushed_tags=false

    # Get local tags first
    local_tags=$(git tag)
    if [ -z "$local_tags" ]; then
        echo "No local tags found."
        echo
    else
        echo "Comparing local tags against remotes..."
        tag_count=0
        total_tags=$(echo "$local_tags" | wc -l)

        # Warning about no-fetch mode
        if [ "$NO_FETCH" = true ]; then
            echo "Note: Running in --no-fetch mode. Using locally cached remote information."
            echo "Results may be incomplete if local cache is out of date."
        fi

        echo "$local_tags" | while read -r tag; do
            # Show progress every 10 tags
            tag_count=$((tag_count + 1))
            if [ $((tag_count % 10)) -eq 0 ]; then
                echo -ne "  Progress: $tag_count/$total_tags tags processed\r"
            fi

            if ! tag_in_remotes "$tag" 2>/dev/null; then
                found_unpushed_tags=true
                tag_sha=$(git rev-parse "$tag" 2>/dev/null)
                author=$(git show -s --format="%an <%ae>" "$tag" 2>/dev/null)
                echo -e "\nTag: $tag"
                echo "  Commit: $tag_sha"
                echo "  Author: $author"
                echo "  Tag message: $(git tag -l -n1 "$tag" 2>/dev/null | sed 's/^[^ ]* *//')"
                echo "  Tag date: $(git log -1 --pretty=%cd --date=local "$tag^{commit}" 2>/dev/null)"
                echo "  Show command: git show $tag"
                echo "  Delete command: git tag -d $tag"
                echo
            fi
        done

        # Final progress update
        echo -e "  Progress: $total_tags/$total_tags tags processed"

        if [ "$found_unpushed_tags" = false ]; then
            echo "No local tags found that aren't in remotes."
        fi
        echo
    fi
else
    display_header "LOCAL TAGS NOT IN REMOTES"
    echo "Tag checking disabled (--no-tags option)."
    echo "Run without --no-tags to check tags (slower)."
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