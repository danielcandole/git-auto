#!/usr/bin/env bash
set -Eeuo pipefail

BASHRC="${BASHRC:-$HOME/.bashrc}"
START_MARKER="# git-auto - - - - - - - - - - - - - - - - - - - -"
END_MARKER="# - - - - - - - - - - - - - - - - - - - -"

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[[ -n "${HOME:-}" && -d "$HOME" ]] || die "HOME is not set to an existing directory."
[[ -f "$BASHRC" && -r "$BASHRC" && -w "$BASHRC" ]] || {
  if [[ ! -e "$BASHRC" ]]; then
    printf 'git-auto is not installed: %s does not exist.\n' "$BASHRC"
    exit 0
  fi
  die "$BASHRC must be a readable and writable regular file."
}
[[ ! -L "$BASHRC" ]] || die "$BASHRC is a symbolic link; refusing to replace it."

marker_status="$(awk -v start="$START_MARKER" -v end="$END_MARKER" '
  $0 == start { starts++ }
  $0 == end { ends++ }
  END {
    if (starts == 0 && ends == 0) print "none";
    else if (starts == 1 && ends == 1) print "one";
    else print "invalid";
  }
' "$BASHRC")"

if [[ "$marker_status" == "none" ]]; then
  echo "git-auto is not installed in $BASHRC. No changes were made."
  exit 0
fi
[[ "$marker_status" == "one" ]] || die "Found duplicate or unmatched 'git-auto' markers in $BASHRC. No changes were made; inspect the file manually."

umask 077
TEMP_FILE="$(mktemp "${BASHRC}.git-auto.XXXXXX")" || die "Could not create temporary file."
BACKUP_FILE="$(mktemp "${BASHRC}.backup.XXXXXX")" || {
  rm -f -- "$TEMP_FILE"
  die "Could not create backup."
}
cleanup() {
  [[ -z "${TEMP_FILE:-}" || ! -e "$TEMP_FILE" ]] || rm -f -- "$TEMP_FILE"
}
trap cleanup EXIT

cp -p -- "$BASHRC" "$BACKUP_FILE" || die "Could not back up $BASHRC."
awk -v start="$START_MARKER" -v end="$END_MARKER" '
  $0 == start { skip=1; next }
  $0 == end && skip { skip=0; next }
  !skip { print }
' "$BASHRC" > "$TEMP_FILE" || die "Could not prepare updated Bash configuration."

chmod --reference="$BASHRC" "$TEMP_FILE" || die "Could not preserve permissions."
mv -f -- "$TEMP_FILE" "$BASHRC" || die "Could not update $BASHRC."
TEMP_FILE=""

printf 'git-auto removed from %s.\n' "$BASHRC"
printf 'Backup: %s\n' "$BACKUP_FILE"
printf 'Only the exact marked git-auto block was removed; all other lines were preserved.\n'
printf '\nTo unload the functions in this terminal, run:\n  source %q\n' "$BASHRC"
printf 'New Bash terminals will no longer load git-auto.\n'
