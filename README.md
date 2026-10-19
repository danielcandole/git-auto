# git-auto

A Bash utility that repeatedly commits repository changes and optionally pushes successful commits to `origin`.

## Features

- `git-commit-auto`: creates local commits only.
- `git-push-auto`: creates commits and pushes them to `origin`.
- Commit messages include a date and sequential ID.
- Counters are persisted per repository and branch and shared by both commands.
- The installer inserts the function definitions directly into `~/.bashrc`.
- Reinstalling replaces the existing managed block instead of duplicating it.
- Uninstallation removes only the exact marked block and backs up `~/.bashrc`.

## Requirements

- Bash 4 or newer.
- Git.
- `sha256sum` or `shasum` (for counter keys).
- A Git repository with the target branch already created locally.
- For `git-push-auto`, an `origin` remote and working Git authentication.

The scripts are intended for Linux and Unix-like systems. They use standard shell utilities such as `awk`, `mktemp`, `chmod`, and `mv`.

## Installation

Clone the repository and enter its directory:

```bash
git clone https://github.com/<YOUR-USERNAME>/git-auto.git
cd git-auto
```

Review the scripts before running them, then install:

```bash
bash install.sh
```

The installer:

1. Validates the existing git-auto markers before changing anything.
2. Creates a uniquely named backup of `~/.bashrc`.
3. Removes any existing valid git-auto block.
4. Inserts the function source directly between the managed markers.
5. Replaces `~/.bashrc` atomically using a temporary file in the same directory.

It refuses to proceed if markers are duplicated or unmatched, or if `~/.bashrc` is a symbolic link. It does not overwrite the rest of your Bash configuration.

**Load the commands in the current terminal:** an executed installer cannot modify its parent shell's environment. After installation, run:

```bash
source ~/.bashrc
```

Alternatively, open a new Bash terminal. Future Bash sessions will load the functions automatically.

Verify:

```bash
type git-commit-auto
type git-push-auto
git-commit-auto --help
git-push-auto --help
```

## Usage

Run these commands **from inside the Git repository** you want to automate.

### Create local commits

```bash
git-commit-auto <branch> "<commit message>" <timer-seconds> [start-id]
```

Example:

```bash
git-commit-auto main "fix billing bug" 30 1
```

### Create commits and push to `origin`

```bash
git-push-auto <branch> "<commit message>" <timer-seconds> [start-id]
```

Example:

```bash
git-push-auto main "fix billing bug" 30 1
```

### Arguments

| Argument | Meaning |
| --- | --- |
| `branch` | Existing local branch to switch to and use |
| `commit message` | Base message; quote it if it contains spaces |
| `timer-seconds` | Positive integer interval between iterations |
| `start-id` | Optional non-negative starting ID; if omitted, the saved counter is used |

Run `Ctrl+C` to stop the loop. The timer is a delay between iterations, not a precise schedule.

## Commit message format

```text
comment:fix billing bug | date:101926 | commit:01
```

- `comment`: The message supplied to the command.
- `date`: The local system date in `MMDDYY` format.
- `commit`: Sequential numeric ID padded to at least two digits (`01`, `02`, …, `100`).

## Counter storage

Counter files are stored under:

```text
${XDG_STATE_HOME:-~/.local/state}/git-auto/
```

The repository path and branch name are hashed to form the counter filename. Both commands use the same counter for the same repository and branch. If `start-id` is supplied, that invocation starts at the provided ID; successful commits then advance the saved counter.

If a push fails, the commit remains in local history and its counter is saved so the ID is not intentionally reused. A lock directory prevents two git-auto loops from running concurrently for the same repository/branch. If a process is forcibly killed, a stale lock may remain; inspect and remove the corresponding `.lock` directory only after confirming no git-auto process is still running.

## What gets committed

The command runs `git add -A`. This stages **all** changes in the repository, including untracked files, modifications, and deletions. Review `git status` first and do not run it if you have unrelated or sensitive changes you do not want committed.

Git hooks and repository configuration still apply. If Git refuses to commit, the command stops and leaves the staged changes available for inspection.

## Uninstallation

From the cloned repository directory:

```bash
bash uninstall.sh
```

The uninstaller verifies that exactly one complete managed block exists, creates a backup, then removes only the text between the exact git-auto start and end marker lines (including those marker lines). If the markers are missing, duplicated, or unmatched, it makes no changes. Your other `.bashrc` content is preserved.

To unload the functions in the current terminal, run:

```bash
source ~/.bashrc
```

Or open a new Bash terminal. Uninstallation does not delete saved counters under `~/.local/state/git-auto/`; remove that directory yourself if you also want to delete the counter history.

Backups are created next to `.bashrc` with names like `.bashrc.backup.XXXXXX`. Keep or remove them according to your needs.

## Safety Notes

- `git add -A` may include sensitive or unrelated changes, so review the working tree before starting.
- The command switches to the requested local branch. Git may refuse if switching would overwrite local changes.
- `git-push-auto` pushes to `origin`, so confirm the remote and branch before use.
- A failed push does not undo the local commit.
- Avoid running multiple loops for the same repository and branch.
- Do not edit the managed block manually. Re-run the installer to replace it.
- Inspect `install.sh` and `uninstall.sh` before running them, as they modify `~/.bashrc`.
