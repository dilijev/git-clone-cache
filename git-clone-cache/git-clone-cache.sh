#!/bin/bash

# Copy this script to a directory in your PATH before the real git binary.
# Rename this script to "git" so that it intercepts git commands.
# This wrapper will cache git clone operations using a local mirror.

# Find real git binary (skip this wrapper by using absolute path)
WRAPPER_PATH=$(cd "$(dirname "$0")" && pwd)/git
REAL_GIT=$(which -a git 2>/dev/null | grep -v "^$WRAPPER_PATH$" | head -1)

if [[ -z "$REAL_GIT" ]] || [[ ! -x "$REAL_GIT" ]]; then
    echo "Error: Could not find git binary" >&2
    exit 1
fi

# Check if "clone" is in the arguments
clone_found=0
for arg in "$@"; do
    if [[ "$arg" == "clone" ]]; then
        clone_found=1
        break
    fi
done

# If no clone, pass through
if [[ $clone_found -eq 0 ]]; then
    exec "$REAL_GIT" "$@"
fi

# Determine cache directory (with env var override)
CACHE_DIR="${GIT_CLONE_CACHE_DIR:=$HOME/.git-clone-cache}"
mkdir -p "$CACHE_DIR"

# Set up log file
LOG_FILE="$CACHE_DIR/git-clone-cache.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [git-clone-cache] $*" | tee -a "$LOG_FILE" >&2
}

# Extract URL from arguments after clone
url=""
skip_next=0
after_clone=0
for arg in "$@"; do
    if [[ "$arg" == "clone" ]]; then
        after_clone=1
        continue
    fi

    if [[ $after_clone -eq 0 ]]; then
        continue
    fi

    if [[ $skip_next -eq 1 ]]; then
        skip_next=0
        continue
    fi

    # Flags that take an argument
    if [[ "$arg" =~ ^(--depth|--single-branch|--branch)$ ]]; then
        skip_next=1
        continue
    fi

    # Skip other flags
    if [[ "$arg" =~ ^- ]]; then
        continue
    fi

    # First non-option argument is the URL
    url="$arg"
    break
done

# If no URL found or it's a local path (determine by checking if the path exists locally), pass through
if [[ -z "$url" ]] || [[ -d "$url" ]] || [[ -f "$url" ]]; then
    echo "[git-clone-cache] No remote URL detected, passing through" >&2
    exec "$REAL_GIT" "$@"
fi


# Compute stable cache key from URL
log "Clone URL: $url"
CACHE_KEY=$(printf '%s' "$url" | sha256sum | cut -d' ' -f1)
log "Cache key (sha256): $CACHE_KEY"
CACHE_MIRROR="$CACHE_DIR/$CACHE_KEY"

# Initialize cache if missing
if [[ ! -d "$CACHE_MIRROR" ]]; then
    log "Initializing cache: $url"
    log "$REAL_GIT clone --mirror $url $CACHE_MIRROR"
    "$REAL_GIT" clone --mirror "$url" "$CACHE_MIRROR" || {
        log "ERROR: Failed to clone to cache"
        exit 1
    }
else
    # Update existing cache
    log "Updating cache mirror"
    log "$REAL_GIT -C $CACHE_MIRROR fetch --all"
    if ! "$REAL_GIT" -C "$CACHE_MIRROR" fetch --all >/dev/null 2>&1; then
        log "WARNING: Failed to update cache, proceeding anyway"
    fi
fi

# Insert cache flags after "clone" in the original arg list
declare -a new_args=()
found_clone=0
for arg in "$@"; do
    new_args+=("$arg")
    if [[ "$arg" == "clone" ]] && [[ $found_clone -eq 0 ]]; then
        found_clone=1
        new_args+=("--reference" "$CACHE_MIRROR")
    fi
done

log "Cloning from local cache"
log "$REAL_GIT ${new_args[*]}"
exec "$REAL_GIT" "${new_args[@]}"
