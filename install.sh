#!/usr/bin/env bash
set -Eeuo pipefail

# This installer modifies only the clearly marked git-auto block in ~/.bashrc.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_FILE="$SCRIPT_DIR/git-auto.sh"
BASHRC="${BASHRC:-$HOME/.bashrc}"
START_MARKER="# git-auto - - - - - - - - - - - - - - - - - - - -"
END_MARKER="# - - - - - - - - - - - - - - - - - - - -"

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[[ -f "$SOURCE_FILE" && -r "$SOURCE_FILE" ]] || die "Cannot read function source: $SOURCE_FILE"
command -v bash >/dev/null 2>&1 || die "Bash is required."
[[ -n "${HOME:-}" && -d "$HOME" ]] || die "HOME is not set to an existing directory."

if [[ -e "$BASHRC" && ! -f "$BASHRC" ]]; then
  die "$BASHRC exists but is not a regular file."
fi
if [[ -L "$BASHRC" ]]; then
  die "$BASHRC is a symbolic link; refusing to replace it for safety."
fi

umask 077
if [[ ! -e "$BASHRC" ]]; then
  ( set -o noclobber; : > "$BASHRC" ) 2>/dev/null || die "Could not create $BASHRC"
  chmod 600 "$BASHRC" || die "Could not set permissions on new $BASHRC"
fi

# Validate markers before making any changes. An incomplete or duplicated managed
# block could otherwise cause unrelated user configuration to be removed.
marker_status="$(awk -v start="$START_MARKER" -v end="$END_MARKER" '
  $0 == start { starts++ }
  $0 == end { ends++ }
  END {
    if (starts == 0 && ends == 0) print "none";
    else if (starts == 1 && ends == 1) print "one";
    else print "invalid";
  }
' "$BASHRC")"
[[ "$marker_status" != "invalid" ]] || die "Found duplicate or unmatched git-auto markers in $BASHRC. No changes were made; inspect the file manually."

# Build temporary files in the same directory so the final rename is atomic.
TEMP_FILE="$(mktemp "${BASHRC}.git-auto.XXXXXX")" || die "Could not create temporary file."
BACKUP_FILE=""
cleanup() {
  [[ -z "${TEMP_FILE:-}" || ! -e "$TEMP_FILE" ]] || rm -f -- "$TEMP_FILE"
  [[ -z "${TEMP_FILE:-}" || ! -e "${TEMP_FILE}.new" ]] || rm -f -- "${TEMP_FILE}.new"
}
trap cleanup EXIT

# Remove only the exact managed block, preserving every line outside it.
awk -v start="$START_MARKER" -v end="$END_MARKER" '
  $0 == start { skip=1; next }
  $0 == end && skip { skip=0; next }
  !skip { print }
' "$BASHRC" > "$TEMP_FILE" || die "Could not prepare updated Bash configuration."

{
  # Keep the user's original content and append a clean, delimited block.
  cat "$TEMP_FILE"
  printf '%s\n' "$START_MARKER"
  cat "$SOURCE_FILE"
  printf '%s\n' "$END_MARKER"
} > "${TEMP_FILE}.new" || die "Could not assemble the new Bash configuration."

if [[ "$marker_status" == "one" ]]; then
  BACKUP_FILE="$(mktemp "${BASHRC}.backup.XXXXXX")" || die "Could not create backup."
  cp -p -- "$BASHRC" "$BACKUP_FILE" || die "Could not back up $BASHRC."
else
  BACKUP_FILE="$(mktemp "${BASHRC}.backup.XXXXXX")" || die "Could not create backup."
  cp -p -- "$BASHRC" "$BACKUP_FILE" || die "Could not back up $BASHRC."
fi

# Preserve existing mode; retain current user's ownership on the replacement.
chmod --reference="$BASHRC" "${TEMP_FILE}.new" || die "Could not preserve permissions."
mv -f -- "${TEMP_FILE}.new" "$BASHRC" || die "Could not install updated $BASHRC."
rm -f -- "$TEMP_FILE"
TEMP_FILE=""

printf 'git-auto installed successfully.\n'
printf 'Updated: %s\nBackup:  %s\n' "$BASHRC" "$BACKUP_FILE"
printf '\nThe current parent shell cannot be changed by an executed child script.\n'
printf 'To load the commands in this terminal now, run: source %s\n' "$BASHRC"
printf 'New Bash terminals will load the functions automatically.\n'
