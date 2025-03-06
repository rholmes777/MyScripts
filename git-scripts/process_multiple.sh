#!/bin/bash
for repo in /path/to/repos/*; do
  if [ -d "$repo/.git" ]; then
    cd "$repo"
    echo "Processing $repo" >> /path/to/output.txt
    ./git_cleanup_info.sh >> /path/to/output.txt
    echo "----------------------------------------" >> /path/to/output.txt
  fi
done
