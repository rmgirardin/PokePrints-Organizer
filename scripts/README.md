# Pokemon Print Sorting Guide

This repo provides scripts to sort monthly Pokemon 3D projects into Pokemon folders, add shortcuts for multi-Pokemon projects, clean naming, and generate a photo index.

## Default Monthly Workflow

Default source:

- `~/Documents/Projects/3D Printer/CAD/MyPokePrints/To Sort`

Default destination root:

- `~/Documents/Projects/3D Printer/CAD/MyPokePrints`

Run from any folder (paths are explicit):

```bash
"/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints/To Sort/scripts/run_pokemon_pipeline.sh" \
  --base-dir "/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints/To Sort" \
  --output-root "/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints" \
  --dry-run \
  --verbose
```

Then apply:

```bash
"/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints/To Sort/scripts/run_pokemon_pipeline.sh" \
  --base-dir "/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints/To Sort" \
  --output-root "/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints" \
  --apply
```

Build the photo directory after sorting:

```bash
"$HOME/Documents/Projects/3D Printer/CAD/MyPokePrints/To Sort/scripts/build_project_photo_directory.sh" \
  --sorted-dir "$HOME/Documents/Projects/3D Printer/CAD/MyPokePrints/Directory" \
  --link-mode copy \
  --apply
```

Default behavior with `--apply` is incremental: new projects are added and existing project photo assets are updated as needed.

By default, manifest mode is append, so existing entries that are not present in the current scan are kept in the gallery.

`index.html` is regenerated each run from the merged manifest (this is expected), so it reflects both newly scanned projects and previously retained entries.

Use `--manifest-mode rewrite` when you want the manifest and gallery to include only the current scan.

Use `--replace` only when you want to fully rebuild `_photo_directory` from scratch (assets + manifest + index).

## What Happens With Existing Destination Folders

Preferred monthly behavior is enabled:

- Projects are moved into existing Pokemon folders under destination root.
- Existing Pokemon folders are reused (no need to manually recreate them).
- Project folders are never merged together.
- If a project folder name already exists, a new separate folder is created with ` (Variant N)` suffix.
- Existing content is not overwritten.

Example:

- Existing: `Pikachu/January 2026 - Pikachu Statue`
- New colliding project becomes: `Pikachu/January 2026 - Pikachu Statue (Variant 2)`

## Important Safety Note For This Layout

When destination root contains source folder (like `MyPokePrints/To Sort`), `run_pokemon_pipeline.sh` auto-skips Stage 2 and Stage 3 (normalize/humanize) for safety.

This prevents rename scripts from touching unrelated folders in the destination root.

If you want Stage 2/3 naming cleanup, use a dedicated output root (example: `MyPokePrints/Sorted by Pokemon`) instead of the parent root.

## Script Reference

### `scripts/run_pokemon_pipeline.sh`

End-to-end runner.

Key flags:

- `--base-dir <path>`
- `--output-dir <name>` (destination under base dir)
- `--output-root <path>` (absolute/relative destination root; overrides `--output-dir`)
- `--dry-run` or `--apply`
- `--transfer-mode move|copy` (default `move`)
- `--shortcut-type alias|symlink` (default `alias`)
- `--verbose`

### `scripts/sort_pokemon_models.sh`

Stage 1 only (sorting + shortcuts + manifest).

Key flags:

- `--base-dir <path>`
- `--output-root <path>` or `--output-dir <name>`
- `--dry-run` or `--apply`
- `--transfer-mode move|copy`
- `--shortcut-type alias|symlink`
- `--verbose`

### `scripts/normalize_sorted_names.sh`

Stage 2 naming normalization (use only on a dedicated sorted root).

### `scripts/humanize_sorted_names.sh`

Stage 3 readability pass (use only on a dedicated sorted root).

### `scripts/build_project_photo_directory.sh`

Builds one-image-per-project gallery from a sorted root.

Behavior:

- Incremental by default (does not require rebuild each run).
- Groups photo assets by Pokemon under `_photo_directory/images/<pokemon>/...`.
- Sorts gallery by Pokemon, then project.
- Prefers `Color` + `1` images when choosing the project preview image.
- Includes project shortcuts (`alias` and `symlink`) by resolving them to their canonical project folders.
- Includes base Pokemon folder entries only when that folder has direct files (ignored when it only contains project subfolders).
- Skips support-only project folders by name (for example: `Single Material`, `Multimaterial`, `Presupported`, `FDM`, `Supported`, `Hinge`).
- Keeps existing manifest rows by default for projects not seen in the current scan (`--manifest-mode append`).
- Rewrites `_photo_directory/index.html` on each apply from the merged manifest so new and existing entries stay in one consistent gallery.

Example:

```bash
"/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints/To Sort/scripts/build_project_photo_directory.sh" \
  --sorted-dir "/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints/Sorted by Pokemon" \
  --apply
```

Rewrite manifest/index to current scan only:

```bash
"/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints/To Sort/scripts/build_project_photo_directory.sh" \
  --sorted-dir "/Users/richgirardin/Documents/Projects/3D Printer/CAD/MyPokePrints/Sorted by Pokemon" \
  --manifest-mode rewrite \
  --apply
```

Key flags:

- `--sorted-dir <path>`
- `--output-dir <name>` (default `_photo_directory`)
- `--dry-run` or `--apply`
- `--link-mode hardlink|symlink|copy` (default `hardlink`)
- `--manifest-mode append|rewrite` (default `append`)
- `--replace` (opt-in full rebuild of `_photo_directory`)
- `--verbose`

Outputs:

- `.../_photo_directory/index.html`
- `.../_photo_directory/_reports/photo_manifest.tsv`
