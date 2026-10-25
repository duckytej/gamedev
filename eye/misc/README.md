# misc

Everything that supports the game but is not the game.

| Folder | What it holds |
| --- | --- |
| `docs/` | `ARCHITECTURE.md` — design; `AUDIT.md` — robustness fixes and known limits |
| `tests/` | headless tests + `run_all.sh` (fails on test or script errors) |
| `tools/` | `backup.sh` — snapshot helper |
| `backup/` | timestamped source snapshots (see below) |

---

## Tests

```bash
misc/tests/run_all.sh
```

The runner imports the project, runs `smoke_test.gd`, `movement_test.gd`,
`traversal_test.gd`, `combat_test.gd`, `threat_test.gd`, `world_test.gd`,
`vitals_test.gd` and `enemy_ai_test.gd`, and fails if a suite fails **or** if any
`SCRIPT ERROR:` / `ERROR:` appears in the output (Godot returns 0 when a script
aborts).

---

## Backups

The `eye` folder is not its own repository, so `misc/tools/backup.sh` snapshots
just its source. That makes each change reversible independently of the larger
project checkout.

```bash
misc/tools/backup.sh before-refactor      # -> misc/backup/0001_before-refactor/
...
misc/tools/backup.sh after-refactor       # -> misc/backup/0002_after-refactor/
```

Each snapshot is a plain copy of `core/`, `player/`, `combat/`, `world/`,
`enemies/`, the addons, `project.godot` and these docs/tests. **Assets are
excluded** (large, and already replaceable). Indexes auto-increment, so newer
snapshots never overwrite older ones.

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
