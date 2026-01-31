#!/bin/bash

# Recursively find all git repos and populate cache

if [[ $# -eq 0 ]]; then
    echo "Usage: find-and-populate-git-cache /path/to/search" >&2
    exit 1
fi

root_dir="$1"

if [[ ! -d "$root_dir" ]]; then
    echo "ERROR: Not a directory: $root_dir" >&2
    exit 1
fi

echo "Searching for git repos in: $root_dir"

# Find all .git directories, extract parent paths, handle whitespace
repos=()
while IFS= read -r -d '' git_dir; do
    repo_path=$(dirname "$git_dir")
    repos+=("$repo_path")
done < <(find "$root_dir" -name ".git" -type d -print0)

if [[ ${#repos[@]} -eq 0 ]]; then
    echo "No git repos found" >&2
    exit 1
fi

echo "Found ${#repos[@]} repo(s), populating cache..."
populate-git-cache "${repos[@]}"
