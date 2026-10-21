# misc

Everything that supports the game but is not the game.

| Folder | What it holds |
| --- | --- |
| `docs/` | `ARCHITECTURE.md` — the design of the project |
| `tests/` | headless tests (`smoke_test.gd`, `movement_test.gd`) |
| `tools/` | `backup.sh` — snapshot helper |
| `backup/` | timestamped source snapshots (see below) |

---

## Backups

This project has no version control, so `misc/tools/backup.sh` snapshots the
source so any change can be reverted.

```bash
misc/tools/backup.sh before-refactor      # -> misc/backup/0001_before-refactor/
...
misc/tools/backup.sh after-refactor       # -> misc/backup/0002_after-refactor/
```

Each snapshot is a plain copy of `core/`, `player/`, `world/`, `enemies/`, the
addons, `project.godot` and these docs/tests. **Assets are excluded** (large, and
already replaceable). Indexes auto-increment, so newer snapshots never overwrite
older ones.

Reverting is deliberately obvious — copy a file back:

```bash
cp misc/backup/0001_before-refactor/player/scripts/player.gd player/scripts/player.gd
```

Diff a file against a snapshot:

```bash
diff -u misc/backup/0001_before-refactor/player/scripts/player.gd player/scripts/player.gd
```

> `misc/backup/.gdignore` makes Godot skip the whole folder. Without it, Godot
> would see duplicate `class_name`s in the snapshots and error on startup. Keep
> it in place.
