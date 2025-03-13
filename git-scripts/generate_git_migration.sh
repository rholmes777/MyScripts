#!/bin/bash

# Simple script to generate git commands for repository migration
# This will scan immediate subdirectories for git repos and output clone commands

echo "# Git repository migration script"
echo "# Generated on $(date)"
echo "# Run this script on your target machine to recreate the repositories"
echo ""
echo "#!/bin/bash"
echo ""

# Iterate through all immediate subdirectories
for dir in */; do
    # Remove trailing slash
    dir=${dir%/}

    # Check if this is a git repository
    if [ -d "$dir/.git" ]; then
        echo "# Processing repository: $dir"

        # Enter the directory
        cd "$dir" || continue

        # Get the URL of the origin remote (will be used for clone)
        origin_url=$(git remote get-url origin 2>/dev/null)

        if [ -n "$origin_url" ]; then
            # Generate clone command
            echo "echo \"Cloning $dir...\""
            echo "git clone \"$origin_url\" \"$dir\""
            echo "cd \"$dir\""

            # Get all remotes except origin
            remotes=$(git remote | grep -v "^origin$")

            # For each remote, generate a remote add command
            for remote in $remotes; do
                remote_url=$(git remote get-url "$remote" 2>/dev/null)
                if [ -n "$remote_url" ]; then
                    echo "git remote add \"$remote\" \"$remote_url\""
                fi
            done

            echo "cd .."
            echo ""
        else
            echo "# Warning: No origin remote found for $dir, skipping"
            echo ""
        fi

        # Return to the original directory
        cd ..
    fi
done

echo "echo \"Git repository migration completed!\""