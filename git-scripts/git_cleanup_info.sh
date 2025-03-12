#!/bin/bash
# git_cleanup_info.sh
# Script to identify all potential changes in local Git repository workspaces
# that are NOT pushed to any remotes (both upstream and origin)
#
# Usage:
#   ./git_cleanup_info.sh [options]
#
# Options:
#   --tags        Check only tags
#   --no-tags     Skip checking tags (much faster for repos with many tags)
#   --fast        Same as --no-tags (fastest mode)

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
ONLY_TAGS=false

for arg in "$@"; do
    case $arg in
        --no-tags)
            NO_TAGS=true
            ;;
        --fast)
            NO_TAGS=true
            ;;
        --tags)
            ONLY_TAGS=true
            ;;
    esac
done

# Get repository name
repo_name=$(basename "$(git rev-parse --show-toplevel)")
echo "Repository: $repo_name"
echo "Date: $(date)"

# Show which features are enabled/disabled
if [ "$NO_TAGS" = true ]; then
    echo "Mode: No tags (skipping tag processing)"
elif [ "$ONLY_TAGS" = true ]; then
    echo "Mode: Tags only"
else
    echo "Mode: Full scan"
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

    # Use ls-remote to check remote tags
    for remote in "${remotes[@]}"; do
        # The format from ls-remote is: <hash>\trefs/tags/<tagname>
        # We need to escape the tag name for regex and use proper pattern
        escaped_tag=$(echo "$tag" | sed 's/[.^$*+?()[\]{|}]/\\&/g')
        if git ls-remote --tags "$remote" 2>/dev/null | grep -q "[[:xdigit:]]\+[[:space:]]refs/tags/$escaped_tag$"; then
            return 0
        fi
    done

    return 1
}

# Check local branches that don't exist in remotes (skip if --tags)
if [ "$ONLY_TAGS" = false ]; then
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

        # Use process substitution instead of a pipeline to preserve variable values
        # This keeps changes to found_unpushed_tags visible to the parent shell
        tag_displayed=false
        while read -r tag; do
            # Show progress every 10 tags, but only if we haven't displayed any tags yet
            tag_count=$((tag_count + 1))
            if [ "$tag_displayed" = false ] && [ $((tag_count % 10)) -eq 0 ]; then
                # Use carriage return to overwrite the previous progress line
                echo -ne "  Progress: $tag_count/$total_tags tags processed\r"
            fi

            if ! tag_in_remotes "$tag" 2>/dev/null; then
                found_unpushed_tags=true

                # Clear the progress line if we're about to display a tag
                if [ "$tag_displayed" = false ]; then
                    # Print enough spaces to overwrite the progress line, then carriage return
                    echo -ne "                                            \r"
                    tag_displayed=true
                fi

                tag_sha=$(git rev-parse "$tag" 2>/dev/null)
                author=$(git show -s --format="%an <%ae>" "$tag" 2>/dev/null)
                echo "Tag: $tag"
                echo "  Commit: $tag_sha"
                echo "  Author: $author"
                echo "  Tag message: $(git tag -l -n1 "$tag" 2>/dev/null | sed 's/^[^ ]* *//')"
                echo "  Tag date: $(git log -1 --pretty=%cd --date=local "$tag^{commit}" 2>/dev/null)"
                echo "  Show command: git show $tag"
                echo "  Delete command: git tag -d $tag"
                echo
            fi
        done < <(echo "$local_tags")

        # Final progress update - only show if no tags were displayed
        if [ "$tag_displayed" = false ]; then
            echo "  Progress: $total_tags/$total_tags tags processed"
        fi

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

# Check for uncommitted changes (skip if --tags)
if [ "$ONLY_TAGS" = false ]; then
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
fi

echo -e "\nDone."
