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
#   --branches    Check only branches
#   --stashes     Check only stashes
#   --no-tags     Skip checking tags (much faster for repos with many tags)
#   --fast        Same as --no-tags (fastest mode)
#   --help        Show this help message
#   --debug       Enable detailed debug logging
#   --limit=N     Process only N tags (for testing)
#   --dump-tags   Dump all remote tag information

# Debug log file
DEBUG_LOG="/tmp/git_cleanup_debug.log"
DEBUG_MODE=false
TAG_LIMIT=0
DUMP_TAGS=false

# Function to log debug messages
debug_log() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "[DEBUG] $(date +%H:%M:%S) - $*" >> "$DEBUG_LOG"
    fi
}

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

# Function to display help message
show_help() {
    echo "Usage: $(basename "$0") [options]"
    echo
    echo "Options:"
    echo "  --tags        Check only tags"
    echo "  --branches    Check only branches"
    echo "  --stashes     Check only stashes"
    echo "  --no-tags     Skip checking tags (much faster for repos with many tags)"
    echo "  --fast        Same as --no-tags (fastest mode)"
    echo "  --help        Show this help message"
    echo "  --debug       Enable detailed debug logging"
    echo "  --limit=N     Process only N tags (for testing)"
    echo "  --dump-tags   Dump all remote tag information"
    echo
    echo "With no options, performs all checks."
    exit 0
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
CHECK_TAGS=true
CHECK_BRANCHES=true
CHECK_STASHES=true
INVALID_ARG=false

# No arguments means check everything
if [ $# -eq 0 ]; then
    CHECK_TAGS=true
    CHECK_BRANCHES=true
    CHECK_STASHES=true
else
    # If any argument is provided, default to checking nothing
    # We'll enable only what's explicitly requested
    CHECK_TAGS=false
    CHECK_BRANCHES=false
    CHECK_STASHES=false

    for arg in "$@"; do
        case $arg in
            --help)
                show_help
                ;;
            --no-tags)
                NO_TAGS=true
                ;;
            --fast)
                NO_TAGS=true
                ;;
            --tags)
                CHECK_TAGS=true
                ;;
            --branches)
                CHECK_BRANCHES=true
                ;;
            --stashes)
                CHECK_STASHES=true
                ;;
            --debug)
                DEBUG_MODE=true
                # Clear the log file
                > "$DEBUG_LOG"
                echo "Debug mode enabled, logging to $DEBUG_LOG"
                ;;
            --dump-tags)
                DUMP_TAGS=true
                ;;
            --limit=*)
                TAG_LIMIT="${arg#*=}"
                if ! [[ "$TAG_LIMIT" =~ ^[0-9]+$ ]]; then
                    echo "Error: --limit must be a number"
                    exit 1
                fi
                echo "Limiting to $TAG_LIMIT tags"
                ;;
            *)
                INVALID_ARG=true
                ;;
        esac
    done

    # Handle invalid arguments
    if [ "$INVALID_ARG" = true ]; then
        echo "Error: Invalid argument(s) provided"
        echo "Run '$(basename "$0") --help' for usage information"
        exit 1
    fi
fi

# If --no-tags is specified, it overrides --tags
if [ "$NO_TAGS" = true ]; then
    CHECK_TAGS=false
fi

# Get repository name
repo_name=$(basename "$(git rev-parse --show-toplevel)")
echo "Repository: $repo_name"
echo "Date: $(date)"

# Show which features are enabled/disabled
echo -n "Mode: "
if [ "$CHECK_TAGS" = true ] && [ "$CHECK_BRANCHES" = true ] && [ "$CHECK_STASHES" = true ]; then
    echo "Full scan"
else
    features=()
    [ "$CHECK_BRANCHES" = true ] && features+=("Branches")
    [ "$CHECK_STASHES" = true ] && features+=("Stashes")
    [ "$CHECK_TAGS" = true ] && features+=("Tags")

    if [ ${#features[@]} -eq 0 ]; then
        echo "No checks enabled (use --help for options)"
    else
        echo "Checking ${features[*]}"
    fi
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
debug_log "Remotes found: ${remotes[*]}"

# Fetch all remotes to ensure we have the latest data
echo "Fetching from remotes (this might take a while for repos with many branches/tags)..."
for remote in "${remotes[@]}"; do
    echo "  - Fetching from $remote..."
    # Use --no-tags to initially fetch without tags for performance
    git fetch "$remote" --prune >/dev/null 2>&1
done

# Only fetch tags if we need to check tags
if [ "$CHECK_TAGS" = true ]; then
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

# Check local branches that don't exist in remotes
if [ "$CHECK_BRANCHES" = true ]; then
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
fi

# Check for stashes
if [ "$CHECK_STASHES" = true ]; then
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

# Dump all remote tag information if requested
if [ "$DUMP_TAGS" = true ]; then
    display_header "REMOTE TAGS"
    for remote in "${remotes[@]}"; do
        echo "Tags in remote '$remote':"
        git ls-remote --tags "$remote"
        echo
    done
fi

# Check local tags that don't exist in remotes
if [ "$CHECK_TAGS" = true ]; then
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

        # If we're limiting the number of tags to process
        if [ "$TAG_LIMIT" -gt 0 ] && [ "$TAG_LIMIT" -lt "$total_tags" ]; then
            echo "Note: Processing only $TAG_LIMIT of $total_tags tags (--limit option)"
            # Get only the first N tags
            local_tags=$(echo "$local_tags" | head -n "$TAG_LIMIT")
            total_tags=$TAG_LIMIT
        fi

        # Add debugging to see what's happening
        echo "Processing $total_tags local tags..."
        debug_log "Processing $total_tags local tags"

        # Cache remote tag data to avoid repeated calls to git ls-remote
        # Create an associative array
        declare -A remote_tags_cache
        for remote in "${remotes[@]}"; do
            debug_log "Fetching tags from remote: $remote"
            remote_tags_cache[$remote]=$(git ls-remote --tags "$remote" 2>/dev/null)
            debug_log "Cached tag data for $remote"
        done

        # Use process substitution instead of a pipeline to preserve variable values
        tag_displayed=false
        while read -r tag; do
            # Show progress every 10 tags, but only if we haven't displayed any tags yet
            tag_count=$((tag_count + 1))
            if [ "$tag_displayed" = false ] && [ $((tag_count % 10)) -eq 0 ]; then
                # Use carriage return to overwrite the previous progress line
                echo -ne "  Progress: $tag_count/$total_tags tags processed\r"
            fi

            debug_log "Checking tag: $tag (${tag_count}/${total_tags})"

            # Check if tag exists in ANY remote (origin OR upstream)
            tag_in_remote=false

            # Escape tag name for grep
            escaped_tag=$(echo "$tag" | sed 's/[.^$*+?()[\]{|}]/\\&/g')
            debug_log "Escaped tag name: $escaped_tag"

            for remote in "${remotes[@]}"; do
                # Get tags from cache instead of calling git ls-remote again
                remote_tags="${remote_tags_cache[$remote]}"

                # Debug the pattern we're looking for
                debug_log "Looking for tag $tag in remote $remote"

                # Look for the tag with a literal tab character
                if echo "$remote_tags" | grep -q $'\t'"refs/tags/$escaped_tag$"; then
                    debug_log "Tag $tag found in $remote (normal tag)"
                    tag_in_remote=true
                    break
                fi

                # Also check for annotated tags with ^{} suffix
                if echo "$remote_tags" | grep -q $'\t'"refs/tags/$escaped_tag\\^{}$"; then
                    debug_log "Tag $tag found in $remote (annotated tag)"
                    tag_in_remote=true
                    break
                fi

                # If we haven't found it, log that information
                if [ "$tag_in_remote" = false ]; then
                    debug_log "Tag $tag not found in $remote"
                fi
            done

            debug_log "Tag $tag exists in remotes: $tag_in_remote"

            # Only display tags that don't exist in ANY remote
            if [ "$tag_in_remote" = false ]; then
                found_unpushed_tags=true
                debug_log "Tag $tag NOT found in any remote - will display"

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
            echo
        fi
    fi
fi

# Check for uncommitted changes
if [ "$CHECK_BRANCHES" = true ]; then
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

debug_log "Script completed successfully"
echo -e "\nDone."