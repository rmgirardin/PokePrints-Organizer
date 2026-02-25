# PokePrints Organizer

![Platform macOS](https://img.shields.io/badge/platform-macOS-black)
![Shell Bash](https://img.shields.io/badge/shell-bash-4EAA25)
[![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Shell scripts for organizing Pokemon 3D-print project folders, standardizing names, and generating a browsable photo directory.

## What this does

- Sorts project folders into Pokemon-centric directories.
- Creates shortcuts for multi-Pokemon projects (`alias` or `symlink`).
- Normalizes folder/file naming in sorted output.
- Applies a readability pass to internal names.
- Generates a photo directory (`Directory.html`) with one preferred image per project.

## Example transformation

Input layout (`To Sort`):

```text
To Sort/
└── January 2026/
	├──Pikachu Statue/
	├── Eevee Pikachu Diorama/
	└── Charizard Bust/
```

Sorted output (`Sorted by Pokemon`):

```text
Sorted by Pokemon/
├── Pikachu/
│   ├── January 2026 - Pikachu Statue/
│   └── Eevee Pikachu Diorama              # canonical OR shortcut
├── Eevee/
│   └── Eevee Pikachu Diorama              # canonical OR shortcut
├── Charizard/
│   └── Charizard Bust/
└── _reports/
```

For multi-Pokemon projects, the scripts create one canonical project folder and place shortcuts (Finder aliases or symlinks) in other matching Pokemon folders.

## Requirements

- macOS (Finder aliases use `osascript`).
- `bash`, `perl`, and standard Unix utilities (`find`, `awk`, `sed`, `sort`, `stat`, `ln`, `cp`, `mv`).
- If you want cross-platform-like shortcut behavior, use `--shortcut-type symlink` instead of Finder aliases.

## Repository layout

- `scripts/run_pokemon_pipeline.sh`: End-to-end runner (sort + normalize + humanize).
- `scripts/sort_pokemon_models.sh`: Stage 1 only (sorting + shortcut creation + manifest).
- `scripts/normalize_sorted_names.sh`: Stage 2 only (project/folder normalization + shortcut recreation).
- `scripts/humanize_sorted_names.sh`: Stage 3 only (readability cleanup).
- `scripts/build_project_photo_directory.sh`: Builds gallery assets and HTML directory.
- `scripts/data/pokedex_token_stream.txt`: Pokemon token catalog used for matching.
- `scripts/data/pokemon_aliases.tsv`: Alias mappings for name detection.

## Quick start

From the repository root:

```bash
./scripts/run_pokemon_pipeline.sh \
  --base-dir "/path/to/To Sort" \
  --output-root "/path/to/Sorted by Pokemon" \
  --dry-run \
  --verbose
```

Apply changes:

```bash
./scripts/run_pokemon_pipeline.sh \
  --base-dir "/path/to/To Sort" \
  --output-root "/path/to/Sorted by Pokemon" \
  --apply
```

Build/update the photo directory:

```bash
./scripts/build_project_photo_directory.sh \
  --sorted-dir "/path/to/Sorted by Pokemon" \
  --apply
```

## Safety and behavior notes

- `--dry-run` is the default for all scripts.
- Existing destination folders are reused; project folders are never merged.
- Name collisions are auto-resolved with ` (Variant N)` suffixes.
- If `--output-root` contains `--base-dir`, pipeline Stage 2 and Stage 3 are auto-skipped for safety.
- Stage 2 and Stage 3 should be run on a dedicated sorted root.

## Photo directory behavior

`build_project_photo_directory.sh`:

- Works incrementally by default.
- Chooses preferred preview images (favoring names that include `Color` and/or `1`).
- Resolves both symlink and Finder alias project shortcuts.
- Skips support-only project names (for example `FDM`, `Single Material`, `Supported`).
- Writes/merges `photo_manifest.tsv` based on `--manifest-mode`:
  - `append` (default): keep old rows not seen in current scan.
  - `rewrite`: only current scan entries.
- Rebuilds `Directory.html` on each apply using merged manifest rows.

Use a full rebuild only when needed:

```bash
./scripts/build_project_photo_directory.sh \
  --sorted-dir "/path/to/Sorted by Pokemon" \
  --replace \
  --manifest-mode rewrite \
  --apply
```

## Script reference

### `run_pokemon_pipeline.sh`

Usage:

```bash
./scripts/run_pokemon_pipeline.sh [options]
```

Key options:

- `--base-dir <path>`
- `--output-dir <name>`
- `--output-root <path>` (overrides `--output-dir`)
- `--dry-run | --apply`
- `--transfer-mode move|copy` (default: `move`)
- `--shortcut-type alias|symlink` (default: `alias`)
- `--skip-normalize`
- `--skip-humanize`
- `--verbose`

### `sort_pokemon_models.sh`

Usage:

```bash
./scripts/sort_pokemon_models.sh [options]
```

Key options:

- `--base-dir <path>`
- `--output-dir <name>`
- `--output-root <path>`
- `--dry-run | --apply`
- `--move | --copy | --transfer-mode move|copy`
- `--shortcut-type alias|symlink`
- `--verbose`

### `normalize_sorted_names.sh`

Usage:

```bash
./scripts/normalize_sorted_names.sh [options]
```

Key options:

- `--sorted-dir <path>`
- `--dry-run | --apply`
- `--shortcut-type preserve|alias|symlink`
- `--verbose`

### `humanize_sorted_names.sh`

Usage:

```bash
./scripts/humanize_sorted_names.sh [options]
```

Key options:

- `--sorted-dir <path>`
- `--dry-run | --apply`
- `--verbose`

### `build_project_photo_directory.sh`

Usage:

```bash
./scripts/build_project_photo_directory.sh [options]
```

Key options:

- `--sorted-dir <path>`
- `--output-dir <name>` (default: `_photo_directory`)
- `--dry-run | --apply`
- `--link-mode hardlink|symlink|copy` (default: `hardlink`)
- `--manifest-mode append|rewrite` (default: `append`)
- `--replace`
- `--verbose`

## Output files

- `Sorted by Pokemon/_reports/sort_manifest.tsv`
- `Sorted by Pokemon/_reports/name_cleanup_project_map.tsv`
- `Sorted by Pokemon/_reports/name_cleanup_file_renames.tsv`
- `Sorted by Pokemon/_reports/name_humanize_internal_renames.tsv`
- `Sorted by Pokemon/_photo_directory/Directory.html`
- `Sorted by Pokemon/_photo_directory/_reports/photo_manifest.tsv`

## Contributing

1. Open an issue first for large behavior changes.
2. Keep dependencies native and script-first (no additional frameworks/tools without discussion).
3. Validate changes with `--dry-run` before `--apply`.
4. Include a small sample input/output tree in PR notes for behavior changes.
5. Update `README.md` and script `--help` text together when flags or defaults change.

## License

MIT. See [`LICENSE`](LICENSE).
