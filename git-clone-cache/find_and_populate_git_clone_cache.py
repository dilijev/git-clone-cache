#!/usr/bin/env python3
"""Recursively find all git repos and populate cache."""

import os
import sys
import subprocess
from pathlib import Path

import populate_git_clone_cache


def run_populate_git_clone_cache(repo_path):
    """Run populate_git_clone_cache for a given repo path, streaming output."""
    info_msg = f"Populating git clone cache for repo: {repo_path}"
    print(f"[find_and_populate_git_clone_cache][INFO] {info_msg}")
    try:
        process = subprocess.Popen(
            [sys.executable, "-m", "populate_git_clone_cache", str(repo_path)],
            stdout=sys.stdout,
            stderr=sys.stderr,
            text=True
        )
        returncode = process.wait()
        if returncode == 0:
            print(f"[find_and_populate_git_clone_cache][INFO] Successfully populated cache for {repo_path}")
        else:
            print(f"[find_and_populate_git_clone_cache][ERROR] Failed to populate cache for {repo_path}. Return code: {returncode}", file=sys.stderr)
    except Exception as e:
        error_msg = f"Exception while populating cache for {repo_path}: {e}"
        print(f"[find_and_populate_git_clone_cache][ERROR] {error_msg}", file=sys.stderr)


def main():
    if len(sys.argv) < 2:
        print("Usage: find-and-populate-git-cache /path/to/search", file=sys.stderr)
        sys.exit(1)

    root_dir = Path(sys.argv[1]).resolve()

    if not root_dir.is_dir():
        print(f"ERROR: Not a directory: {root_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Searching for git repos in: {root_dir}")

    # Find all .git directories
    repos = []
    for root, dirs, files in os.walk(root_dir, followlinks=False):
        if '.git' in dirs:
            found = Path(root) / '.git'
            print(f"Found git repo: {found}")
            repos.append(root)

        dirs[:] = [
            d for d in dirs
            if d not in {".git", "node_modules"}
            and not os.path.islink(os.path.join(root, d))
        ]

        if '.git' in dirs:
            found = Path(root) / '.git'
            print(f"Found git repo: {found}")
            repos.append(root)

    if not repos:
        print("No git repos found", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(repos)} repo(s), populating cache...")

    for repo in repos:
        run_populate_git_clone_cache(repo)


if __name__ == "__main__":
    main()
