#!/usr/bin/env python3

import os
import sys
import hashlib
import subprocess
import shutil
from pathlib import Path
import json


def info(msg):
    print(f"[populate_git_clone_cache][INFO] {msg}")


def verbose(msg):
    # print(f"[populate_git_clone_cache][VERBOSE] {msg}", file=sys.stderr)
    pass


def error(msg):
    print(f"[populate_git_clone_cache][ERROR] {msg}", file=sys.stderr)


def find_real_git():
    """Find the real git binary, skipping the wrapper at ~/bin/git"""
    exe_name = "git" + (".exe" if os.name == "nt" else "")
    wrapper_path = Path(__file__).parent / "out" / exe_name
    verbose(f"Wrapper path: {wrapper_path}")
    # if windows, use
    wrapper_resolved = wrapper_path.resolve()
    verbose(f"Looking for real git binary. Wrapper path: {wrapper_path}, resolved: {wrapper_resolved}")
    git_path = shutil.which("git")
    verbose(f"shutil.which('git') returned: {git_path}")
    if git_path and Path(git_path).resolve() != wrapper_resolved:
        verbose(f"Using git binary: {git_path}")
        return git_path
    verbose("Could not find a suitable git binary (skipping wrapper)")
    return None


def get_origin_url(repo_path, real_git):
    """Extract origin URL from a local git repo"""
    info(f"Getting origin URL for repo: {repo_path}")
    try:
        result = subprocess.run(
            [real_git, "-C", str(repo_path), "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            check=False
        )
        verbose(f"Command output: {result.stdout.strip()}, returncode: {result.returncode}")
        if result.returncode == 0:
            return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        error(f"Exception while getting origin URL: {e}")
    return None


def compute_cache_key(url):
    """Compute SHA256 hash of URL"""
    info(f"Computing cache key for URL: {url}")
    key = hashlib.sha256(url.encode()).hexdigest()
    info(f"Cache key: {key}")
    return key


def is_local_repo(path):
    """Check if path is a git repository"""
    path_obj = Path(path)
    verbose(f"Checking if path is a local git repo: {path}")
    is_repo = path_obj.is_dir() and path_obj.joinpath(".git").exists()
    verbose(f"is_local_repo({path}) = {is_repo}")
    return is_repo


def run_git_command(cmd, args):
    """Run a git command and return success status"""
    info(f"Running git command: {cmd} {' '.join(args)}")
    try:
        result = subprocess.run([cmd] + args, check=True, capture_output=True)
        verbose(f"Command succeeded. stdout: {result.stdout}, stderr: {result.stderr}")
        return True
    except subprocess.CalledProcessError as e:
        error(f"Command failed: {e}. stdout: {e.stdout}, stderr: {e.stderr}")
        return False


def update_directory_json(cache_dir, url, cache_key):
    """Update directory.json mapping URL to cache_key"""
    directory_json_path = cache_dir / "directory.json"
    mapping = {}
    if directory_json_path.exists():
        try:
            with open(directory_json_path, "r") as f:
                mapping = json.load(f)
        except Exception as e:
            error(f"Failed to read directory.json: {e}")
    # Idempotent update
    if mapping.get(url) != cache_key:
        mapping[url] = cache_key
        try:
            with open(directory_json_path, "w") as f:
                json.dump(mapping, f, indent=2, sort_keys=True)
            info(f"Updated directory.json for {url}")
        except Exception as e:
            error(f"Failed to write directory.json: {e}")


def set_origin_url(cache_mirror, real_git, url):
    """Set the origin URL for the mirror repo"""
    info(f"Setting origin URL for cache mirror: {cache_mirror}")
    # This is idempotent: setting the same URL repeatedly is safe
    return run_git_command(
        real_git, ["-C", str(cache_mirror), "remote", "set-url", "origin", url]
    )


def populate_cache(url, cache_mirror, real_git, source_for_clone, cache_dir):
    """Create or update a cache entry and update directory.json"""
    verbose(f"populate_cache called with url={url}, cache_mirror={cache_mirror}, source_for_clone={source_for_clone}")
    if cache_mirror.exists():
        info(f"Updating: {url}")
        verbose(f"Cache mirror exists: {cache_mirror}")
        updated = run_git_command(
            real_git, ["-C", str(cache_mirror), "fetch", "--all"]
        )
        # Ensure origin URL is correct (idempotent)
        set_origin_url(cache_mirror, real_git, url)
        update_directory_json(cache_dir, url, cache_mirror.name)
        if updated:
            verbose("  -> OK")
            return True
        else:
            error(f"Failed to update cache for {url}")
            return False
    else:
        info(f"Caching: {url}")
        verbose(f"Cache mirror does not exist, cloning to: {cache_mirror}")
        cloned = run_git_command(
            real_git, ["clone", "--mirror", source_for_clone, str(cache_mirror)]
        )
        if cloned:
            info(f"  -> {cache_mirror}")
            # Set origin URL to the actual remote URL (idempotent)
            set_origin_url(cache_mirror, real_git, url)
            update_directory_json(cache_dir, url, cache_mirror.name)
            return True
        else:
            error(f"Failed to cache {url}")
            return False


def main():
    verbose("Script started.")
    real_git = find_real_git()
    info(f"real_git resolved to: {real_git}")
    if not real_git or not os.access(real_git, os.X_OK):
        error("Could not find git binary")
        error("Exiting due to missing git binary.")
        sys.exit(1)

    cache_dir_env = os.environ.get("GIT_CLONE_CACHE_DIR")
    verbose(f"GIT_CLONE_CACHE_DIR env: {cache_dir_env}")
    cache_dir = Path(
        cache_dir_env if cache_dir_env else os.path.expanduser("~/.git-clone-cache")
    )
    verbose(f"Using cache_dir: {cache_dir}")
    cache_dir.mkdir(parents=True, exist_ok=True)
    verbose(f"Ensured cache_dir exists: {cache_dir}")

    if len(sys.argv) < 2:
        prog_name = Path(sys.argv[0]).name
        error(
            f"Usage: {prog_name} /path/to/repo1 [/path/to/repo2 ...] "
            "[https://url ...]"
        )
        verbose("Exiting due to missing arguments.")
        sys.exit(1)

    for arg in sys.argv[1:]:
        verbose(f"Processing argument: {arg}")
        arg_path = Path(arg)

        if not arg_path.exists():
            error(f"Path does not exist: {arg}")
            continue

        if is_local_repo(arg):
            verbose(f"Argument is a local repo: {arg}")
            url = get_origin_url(arg_path, real_git)
            if not url:
                error(f"WARNING: No origin remote in {arg}, skipping")
                continue
            source_for_clone = arg
        elif arg_path.is_dir():
            error(f"Not a git repo: {arg}")
            verbose(f"Argument is a directory but not a git repo: {arg}")
            continue
        else:
            verbose(f"Argument is treated as URL: {arg}")
            url = arg
            source_for_clone = url

        cache_key = compute_cache_key(url)
        cache_mirror = cache_dir / cache_key
        verbose(f"Cache mirror path: {cache_mirror}")

        populate_cache(url, cache_mirror, real_git, source_for_clone, cache_dir)

    info("Done.")
    verbose("Script finished.")


if __name__ == "__main__":
    main()
