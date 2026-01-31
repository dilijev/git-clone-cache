#!/usr/bin/env python3
"""Recursively find all git repos and populate cache."""

import os
import sys
import subprocess
from pathlib import Path

import populate_git_clone_cache


VERBOSE=False


def info(msg, log_file=None):
    formatted = f"[find_and_populate_git_clone_cache][INFO] {msg}";
    print(formatted)
    if log_file:
        log_file.write(formatted + "\n")


def verbose(msg, log_file=None):
    if not VERBOSE:
        return

    formatted = f"[find_and_populate_git_clone_cache][VERBOSE] {msg}";
    print(formatted)
    if log_file:
        log_file.write(formatted + "\n")


def error(msg, log_file=None):
    formatted = f"[find_and_populate_git_clone_cache][ERROR] {msg}"
    print(formatted, file=sys.stderr)
    if log_file:
        log_file.write(formatted + "\n")


def get_log_file(cache_dir):
    log_path = cache_dir / "find_and_populate_git_clone_cache.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    return open(log_path, "a", buffering=1)


def run_populate_git_clone_cache(repo_path, log_file=None):
    info_msg = f"Populating git clone cache for repo: {repo_path}"
    info(info_msg, log_file)
    try:
        process = subprocess.Popen(
            [sys.executable, "-m", "populate_git_clone_cache", str(repo_path)],
            stdout=sys.stdout,
            stderr=sys.stderr,
            text=True
        )
        returncode = process.wait()
        if returncode == 0:
            info(f"Successfully populated cache for {repo_path}", log_file)
        else:
            error(f"Failed to populate cache for {repo_path}. Return code: {returncode}", log_file)
    except Exception as e:
        error(f"Exception while populating cache for {repo_path}: {e}", log_file)


def main():
    if len(sys.argv) < 2:
        error("Usage: find-and-populate-git-cache /path/to/search")
        sys.exit(1)

    root_dir = Path(sys.argv[1]).resolve()

    if not root_dir.is_dir():
        error(f"ERROR: Not a directory: {root_dir}")
        sys.exit(1)

    cache_dir = Path(
        os.environ.get("GIT_CLONE_CACHE_DIR", os.path.expanduser("~/.git-clone-cache"))
    )
    log_file = get_log_file(cache_dir)

    info(f"Searching for git repos in: {root_dir}", log_file)

    repos = []
    for root, dirs, files in os.walk(root_dir, followlinks=False):
        if '.git' in dirs:
            found = Path(root) / '.git'
            info(f"Found git repo: {found}", log_file)
            repos.append(root)
        dirs[:] = [
            d for d in dirs
            if d not in {".git", "node_modules"}
            and not os.path.islink(os.path.join(root, d))
        ]
        if '.git' in dirs:
            found = Path(root) / '.git'
            info(f"Found git repo: {found}", log_file)
            repos.append(root)

    if not repos:
        error("No git repos found", log_file)
        sys.exit(1)

    info(f"Found {len(repos)} repo(s), populating cache...", log_file)

    for repo in repos:
        run_populate_git_clone_cache(repo, log_file=log_file)

    info("Done.", log_file)
    log_file.write("Done.\n")
    log_file.close()

if __name__ == "__main__":
    main()
