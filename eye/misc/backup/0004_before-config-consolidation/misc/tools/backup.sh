#!/usr/bin/env bash
#
# Snapshot the eye project's source into misc/backup/<NNNN>_<label>/.
#
# Backups are plain copies of the code/scenes/config/docs (NOT assets or the
# .godot cache), so you can diff or restore any file without git.
#
# Usage:
#   misc/tools/backup.sh before-refactor
#   misc/tools/backup.sh            # label defaults to "snapshot"
#
# Restoring is intentionally manual and obvious: copy a file back from the
# snapshot, e.g.
#   cp misc/backup/0002_after/player/scripts/player.gd player/scripts/player.gd
#
set -euo pipefail

EYE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$EYE_DIR/misc/backup"
mkdir -p "$BACKUP_DIR"

label="${1:-snapshot}"

last="$(ls -1 "$BACKUP_DIR" 2>/dev/null | grep -E '^[0-9]{4}_' | sort | tail -n1 || true)"
if [ -n "$last" ]; then
  n=$(( 10#${last%%_*} + 1 ))
else
  n=1
fi
idx="$(printf '%04d' "$n")"
dest="$BACKUP_DIR/${idx}_${label}"

# Godot must never scan backups (duplicate class_names). Keep this file in place.
touch "$BACKUP_DIR/.gdignore"

mkdir -p "$dest"

# Code, scenes, config, docs and tests. Assets are excluded on purpose (large,
# and already replaceable). Add more paths here as the project grows.
items=(
  core
  player
  world
  enemies
  addons/screenspace_projection
  addons/eye_postfx
  misc/docs
  misc/tests
  misc/tools
  README.md
  misc/README.md
  project.godot
  .editorconfig
  .gitattributes
  .gitignore
)

for item in "${items[@]}"; do
  if [ -e "$EYE_DIR/$item" ]; then
    mkdir -p "$dest/$(dirname "$item")"
    cp -r "$EYE_DIR/$item" "$dest/$item"
  fi
done

echo "backup: $dest"
