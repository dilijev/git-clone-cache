#!/bin/bash

# Populate/update git clone cache from local repos or URLs

# Find real git binary (skip this wrapper by using absolute path)
WRAPPER_PATH=$(cd "$(dirname "$0")" && pwd)/git
REAL_GIT=$(which -a git 2>/dev/null | grep -v "^$WRAPPER_PATH$" | head -1)

if [[ -z "$REAL_GIT" ]] || [[ ! -x "$REAL_GIT" ]]; then
    echo "Error: Could not find git binary" >&2
    exit 1
fi

CACHE_DIR="${GIT_CLONE_CACHE_DIR:=$HOME/.git-clone-cache}"
mkdir -p "$CACHE_DIR"

if [[ $# -eq 0 ]]; then
    echo "Usage: populate-git-cache /path/to/repo1 [/path/to/repo2 ...] [https://url ...]" >&2
    exit 1
fi

for arg in "$@"; do
    if [[ -d "$arg/.git" ]]; then
        # It's a local repo, extract origin URL
        url=$("$REAL_GIT" -C "$arg" remote get-url origin 2>/dev/null)
        if [[ -z "$url" ]]; then
            echo "WARNING: No origin remote in $arg, skipping" >&2
            continue
        fi
        is_local_repo=1
    elif [[ -d "$arg" ]]; then
        # Directory but not a repo
        echo "ERROR: Not a git repo: $arg" >&2
        continue
    else
        # Assume it's a URL
        url="$arg"
        is_local_repo=0
    fi

    # Compute cache key (same as wrapper)
    cache_key=$(printf '%s' "$url" | sha256sum | cut -d' ' -f1)
    cache_mirror="$CACHE_DIR/$cache_key"

    if [[ -d "$cache_mirror" ]]; then
        # Already cached, update it
        echo "Updating: $url"
        echo "[populate-git-cache] $REAL_GIT -C $cache_mirror fetch --all" >&2
        if "$REAL_GIT" -C "$cache_mirror" fetch --all; then
            echo "  -> OK"
        else
            echo "ERROR: Failed to update cache for $url" >&2
        fi
    else
        # New cache entry
        echo "Caching: $url"

        if [[ $is_local_repo -eq 1 ]]; then
            # Clone from local path (fast, uses hardlinks)
            echo "[populate-git-cache] $REAL_GIT clone --mirror $arg $cache_mirror" >&2
            if "$REAL_GIT" clone --mirror "$arg" "$cache_mirror"; then
                echo "  -> $cache_mirror"
            else
                echo "ERROR: Failed to cache $url" >&2
            fi
        else
            # Clone from remote URL
            echo "[populate-git-cache] $REAL_GIT clone --mirror $url $cache_mirror" >&2
            if "$REAL_GIT" clone --mirror "$url" "$cache_mirror"; then
                echo "  -> $cache_mirror"
            else
                echo "ERROR: Failed to cache $url" >&2
            fi
        fi
    fi
done

echo "Done."
