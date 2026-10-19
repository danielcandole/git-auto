# git-auto functions
_git_auto() {
  local mode="${1:-}"
  shift || true

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage:
  git-commit-auto <branch> "<commit message>" <timer-seconds> [start-id]
  git-push-auto   <branch> "<commit message>" <timer-seconds> [start-id]

Arguments:
  branch            Existing local Git branch
  commit message     Base commit message (quote messages containing spaces)
  timer-seconds      Positive interval between iterations
  start-id           Optional non-negative starting ID

Behavior:
  - Commit format: comment:<message> | date:MMDDYY | commit:01
  - Counters are stored per repository and branch under
    ~/.local/state/git-auto/ and shared by both commands.
  - If start-id is omitted, the saved next ID is used (or 1 initially).
  - Iterations with no staged changes are skipped.
  - git-commit-auto creates local commits only.
  - git-push-auto pushes successful commits to origin.
  - Press Ctrl+C to stop.
HELP
    return 0
  fi

  if [[ $# -lt 3 || $# -gt 4 ]]; then
    printf 'Error: Invalid number of arguments.\nRun "%s --help" for usage.\n' "$mode" >&2
    return 2
  fi

  local branch="$1"
  local comment="$2"
  local timer="$3"
  local start_id="${4:-}"
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/git-auto"
  local state_file repo_root repo_hash branch_hash count date_stamp
  local formatted_id commit_message next_count tmp_state
  local lock_dir=""
  local cleanup_needed=0

  if ! command -v git >/dev/null 2>&1; then
    echo "Error: Git is not installed or not on PATH." >&2
    return 1
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Not inside a Git repository." >&2
    return 1
  fi
  if [[ -z "$branch" || -z "$comment" ]]; then
    echo "Error: Branch and commit message cannot be empty." >&2
    return 2
  fi
  if [[ ! "$timer" =~ ^[0-9]{1,9}$ ]] || (( 10#$timer < 1 )); then
    echo "Error: Timer must be a positive integer (1–999999999)." >&2
    return 2
  fi
  if [[ -n "$start_id" && ( ! "$start_id" =~ ^[0-9]{1,9}$ ) ]]; then
    echo "Error: start-id must be a non-negative integer with at most 9 digits." >&2
    return 2
  fi
  if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    printf "Error: Invalid branch name '%s'.\n" "$branch" >&2
    return 2
  fi
  if ! git show-ref --verify --quiet "refs/heads/$branch"; then
    printf "Error: Local branch '%s' does not exist.\n" "$branch" >&2
    return 1
  fi
  if [[ "$mode" == "git-push-auto" ]] && ! git remote get-url origin >/dev/null 2>&1; then
    echo "Error: Remote 'origin' is not configured." >&2
    return 1
  fi

  repo_root="$(git rev-parse --show-toplevel)" || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    repo_hash="$(printf '%s' "$repo_root" | sha256sum | awk '{print $1}')" || return 1
    branch_hash="$(printf '%s' "$branch" | sha256sum | awk '{print $1}')" || return 1
  elif command -v shasum >/dev/null 2>&1; then
    repo_hash="$(printf '%s' "$repo_root" | shasum -a 256 | awk '{print $1}')" || return 1
    branch_hash="$(printf '%s' "$branch" | shasum -a 256 | awk '{print $1}')" || return 1
  else
    echo "Error: sha256sum or shasum is required to identify repository counters." >&2
    return 1
  fi
  state_file="$state_dir/$repo_hash-$branch_hash.counter"

  if ! mkdir -p "$state_dir"; then
    printf "Error: Cannot create state directory: %s\n" "$state_dir" >&2
    return 1
  fi
  if [[ -n "$start_id" ]]; then
    count="$start_id"
  elif [[ -f "$state_file" ]]; then
    if ! IFS= read -r count < "$state_file" || [[ ! "$count" =~ ^[0-9]{1,9}$ ]]; then
      printf "Error: Invalid saved counter in %s\n" "$state_file" >&2
      return 1
    fi
  else
    count=1
  fi

  # Prevent two git-auto loops for the same repository/branch from racing.
  lock_dir="$state_file.lock"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    printf "Error: Another git-auto process may already be running for this repository and branch (lock: %s).\n" "$lock_dir" >&2
    return 1
  fi
  cleanup_needed=1
  trap 'if [[ "$cleanup_needed" == 1 && -n "$lock_dir" ]]; then rmdir "$lock_dir" 2>/dev/null || true; fi' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if ! git switch "$branch"; then
    printf "Error: Could not switch to '%s'. Check for uncommitted changes or branch conflicts.\n" "$branch" >&2
    return 1
  fi

  printf 'Mode: %s\nBranch: %s\nStarting commit ID: %s\nInterval: %s seconds\nPress Ctrl+C to stop.\n' \
    "$mode" "$branch" "$count" "$timer"

  while true; do
    date_stamp="$(date +%m%d%y)" || return 1
    formatted_id="$(printf '%02d' "$((10#$count))")"
    commit_message="comment:$comment | date:$date_stamp | commit:$formatted_id"

    if ! git add -A; then
      echo "Error: git add failed. Stopping." >&2
      return 1
    fi

    if git diff --cached --quiet; then
      printf '[%s] No changes to commit.\n' "$formatted_id"
    else
      if ! git commit -m "$commit_message"; then
        echo "Error: git commit failed. Stopping. Review Git's output; staged changes were not discarded." >&2
        return 1
      fi

      next_count=$((10#$count + 1))
      if (( next_count > 999999999 )); then
        echo "Error: Commit ID limit reached; refusing to write an unsupported counter." >&2
        return 1
      fi

      tmp_state="$(mktemp "$state_dir/.counter.XXXXXX")" || {
        echo "Error: Commit succeeded, but a temporary counter file could not be created." >&2
        return 1
      }
      if ! printf '%s\n' "$next_count" > "$tmp_state" || ! mv -f -- "$tmp_state" "$state_file"; then
        rm -f -- "$tmp_state"
        echo "Error: Commit succeeded, but the next counter could not be saved. Do not assume the counter advanced." >&2
        return 1
      fi
      count="$next_count"

      if [[ "$mode" == "git-push-auto" ]]; then
        if ! git push origin "$branch"; then
          echo "Error: Push failed. The commit remains local and its ID has been saved." >&2
          return 1
        fi
        printf 'Successfully committed and pushed: %s\n' "$commit_message"
      else
        printf 'Successfully committed locally: %s\n' "$commit_message"
      fi
    fi

    sleep "$timer"
  done
}

git-commit-auto() {
  _git_auto git-commit-auto "$@"
}

git-push-auto() {
  _git_auto git-push-auto "$@"
}
