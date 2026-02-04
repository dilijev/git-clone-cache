#!/bin/bash
#
# git-clone-cache-alias.sh
#
# Create symlink aliases inside ~/.git-clone-cache so multiple URL hashes
# resolve to the same canonical cache directory (one on-disk repo/object store).
#
# Usage:
#   git-clone-cache-alias.sh <canonical_url> <alias_url> [<alias_url> ...]
#
# Examples:
#   git-clone-cache-alias.sh https://github.com/chromium/chromium \
#     https://chromium.googlesource.com/chromium/src \
#     https://chromium.googlesource.com/chromium/src.git
#
# Env:
#   GIT_CLONE_CACHE_DIR  Override cache directory (default: ~/.git-clone-cache)
#   DRY_RUN=1            Print actions, do not modify filesystem
#
# Notes:
# - Creates symlink: ~/.git-clone-cache/<sha256(alias_url)> -> <sha256(canonical_url)>
# - Refuses to overwrite a real directory unless --force is provided.
# - If the alias path already exists and is the correct symlink, it's a no-op.
#

set -euo pipefail

CACHE_DIR="${GIT_CLONE_CACHE_DIR:=$HOME/.git-clone-cache}"
mkdir -p "$CACHE_DIR"

LOG_FILE="$CACHE_DIR/git-clone-cache-alias.log"
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [git-clone-cache-alias] $*" | tee -a "$LOG_FILE" >&2
}

usage() {
  cat >&2 <<EOF
Usage:
  $(basename "$0") [--force] [--no-log] <canonical_url> <alias_url> [<alias_url> ...]

Options:
  --force     If alias key path exists as a real directory or wrong symlink, replace it.
  --no-log    Don't append to $LOG_FILE (still prints to stderr).
Env:
  GIT_CLONE_CACHE_DIR  Cache root (default: ~/.git-clone-cache)
  DRY_RUN=1            Print actions without changing filesystem

EOF
  exit 2
}

FORCE=0
NO_LOG=0

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --no-log) NO_LOG=1; shift ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) log "ERROR: Unknown option: $1"; usage ;;
    *) break ;;
  esac
done

# If --no-log, redefine log to avoid file append
if [[ "$NO_LOG" -eq 1 ]]; then
  log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [git-clone-cache-alias] $*" >&2; }
fi

if [[ $# -lt 2 ]]; then
  usage
fi

canonical_url="$1"; shift
alias_urls=("$@")

sha_key() {
  # sha256sum output differs on macOS vs GNU; handle both.
  # Prefer sha256sum if available, else shasum -a 256.
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    log "ERROR: Need sha256sum or shasum"
    exit 1
  fi
}

realpath_f() {
  # Portable realpath fallback for macOS if realpath isn't present.
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    python3 - <<PY
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
  fi
}

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "DRY_RUN: $*"
  else
    eval "$@"
  fi
}

# Path to directory.json
DIRECTORY_JSON="$CACHE_DIR/directory.json"

update_directory_json() {
    local url="$1"
    local cache_key="$2"
    # If jq is available, use it for robust JSON handling
    if command -v jq >/dev/null 2>&1; then
        if [[ ! -f "$DIRECTORY_JSON" ]]; then
            echo '{}' > "$DIRECTORY_JSON"
        fi
        tmpfile=$(mktemp)
        jq --arg url "$url" --arg key "$cache_key" \
            '.[$url] = $key' \
            "$DIRECTORY_JSON" > "$tmpfile" && mv "$tmpfile" "$DIRECTORY_JSON"
    else
        # refuse to edit directory.json without jq
        log "WARNING: jq not found, skipping update of directory.json"
    fi
}

canonical_key="$(sha_key "$canonical_url")"
canonical_path="$CACHE_DIR/$canonical_key"

log "Canonical URL: $canonical_url"
log "Canonical key: $canonical_key"
log "Canonical dir: $canonical_path"

if [[ ! -d "$canonical_path" ]]; then
  log "ERROR: Canonical cache dir does not exist: $canonical_path"
  log "Hint: run a cached clone for the canonical URL first so the mirror exists."
  exit 1
fi

# Safety: if canonical_path is a symlink, normalize to its real target (fine either way)
canonical_real="$(realpath_f "$canonical_path")"
log "Canonical realpath: $canonical_real"

for aurl in "${alias_urls[@]}"; do
  alias_key="$(sha_key "$aurl")"
  alias_path="$CACHE_DIR/$alias_key"

  log "Alias URL: $aurl"
  log "Alias key: $alias_key"
  log "Alias path: $alias_path"

  # If alias path exists...
  if [[ -L "$alias_path" ]]; then
    # Existing symlink: check if it already points at canonical_key (or canonical_real).
    target="$(readlink "$alias_path")"
    # Resolve relative targets relative to cache dir
    if [[ "$target" != /* ]]; then
      target_resolved="$(realpath_f "$CACHE_DIR/$target")"
    else
      target_resolved="$(realpath_f "$target")"
    fi

    if [[ "$target_resolved" == "$canonical_real" ]]; then
      log "OK: alias already points to canonical (no-op)"
      continue
    fi

    if [[ "$FORCE" -eq 0 ]]; then
      log "ERROR: alias exists but points elsewhere: $alias_path -> $target"
      log "       Use --force to replace it."
      exit 1
    fi

    log "Replacing existing symlink (force): $alias_path -> $target"
    run "rm -f \"\$alias_path\""
  elif [[ -e "$alias_path" ]]; then
    # Exists but not a symlink (file/dir)
    if [[ "$FORCE" -eq 0 ]]; then
      log "ERROR: alias path exists and is not a symlink: $alias_path"
      log "       Refusing to overwrite. Use --force if you're sure."
      exit 1
    fi

    log "Removing existing path (force): $alias_path"
    run "rm -rf \"\$alias_path\""
  fi

  # Create symlink (relative within cache dir is nicer/portable)
  log "Creating symlink: $alias_key -> $canonical_key"
  run "ln -s \"\$canonical_key\" \"\$alias_path\""

  # Verify
  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    vtarget="$(readlink "$alias_path")"
    log "Created: $alias_path -> $vtarget"
  fi

  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    # Update directory.json for this alias
    update_directory_json "$aurl" "$alias_key"
  fi

  # Add alias URL as a remote in the canonical repo
  # Normalize remote name: replace :/. with -
  remote_name="$(echo "$aurl" | sed 's/[:\/.]/-/g')"
  git_dir="$canonical_path"
  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    if git --git-dir="$git_dir" remote | grep -qxF "$remote_name"; then
      log "Remote '$remote_name' already exists in $git_dir, skipping add."
    else
      log "Adding remote '$remote_name' -> $aurl in $git_dir"
      git --git-dir="$git_dir" remote add "$remote_name" "$aurl" || log "WARNING: Could not add remote $remote_name"
    fi
  else
    log "DRY_RUN: Would add remote '$remote_name' -> $aurl in $git_dir"
  fi
done

log "Done."
