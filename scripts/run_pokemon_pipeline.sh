#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run the full Pokemon organization pipeline in one command.

Usage:
  run_pokemon_pipeline.sh [--base-dir <path>] [--output-dir <name>] [--output-root <path>] [--dry-run|--apply] [--transfer-mode <move|copy>] [--shortcut-type <alias|symlink>] [--verbose]

Options:
  --base-dir <path>            Base directory to sort. Default: current directory
  --output-dir <name>          Sorted output folder name. Default: Sorted by Pokemon
  --output-root <path>         Absolute/relative output root path. Overrides --output-dir
  --dry-run                    Plan only (default)
  --apply                      Apply all stages
  --transfer-mode <move|copy>  Sort transfer mode. Default: move
  --shortcut-type <alias|symlink>  Multi-Pokemon shortcut type. Default: alias
  --alias-shortcuts            Use Finder aliases for shortcuts (default)
  --symlink-shortcuts          Use symbolic links for shortcuts
  --verbose                    Pass verbose mode to all stages
  --skip-normalize             Skip project/file normalization stage
  --skip-humanize              Skip readability rename stage
  -h, --help                   Show help
EOF
}

err() {
  echo "Error: $*" >&2
  exit 1
}

to_abs_path() {
  perl -MFile::Spec -e 'print File::Spec->rel2abs($ARGV[0])' "$1"
}

BASE_DIR="."
OUTPUT_DIR_NAME="Sorted by Pokemon"
OUTPUT_ROOT_OVERRIDE=""
MODE="dry-run"
TRANSFER_MODE="move"
SHORTCUT_TYPE="alias"
VERBOSE=0
SKIP_NORMALIZE=0
SKIP_HUMANIZE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-dir)
      shift
      [ "$#" -gt 0 ] || err "--base-dir requires a value"
      BASE_DIR="$1"
      ;;
    --output-dir)
      shift
      [ "$#" -gt 0 ] || err "--output-dir requires a value"
      OUTPUT_DIR_NAME="$1"
      ;;
    --output-root)
      shift
      [ "$#" -gt 0 ] || err "--output-root requires a value"
      OUTPUT_ROOT_OVERRIDE="$1"
      ;;
    --dry-run)
      MODE="dry-run"
      ;;
    --apply)
      MODE="apply"
      ;;
    --transfer-mode)
      shift
      [ "$#" -gt 0 ] || err "--transfer-mode requires a value"
      case "$1" in
        move|copy)
          TRANSFER_MODE="$1"
          ;;
        *)
          err "--transfer-mode must be 'move' or 'copy'"
          ;;
      esac
      ;;
    --shortcut-type)
      shift
      [ "$#" -gt 0 ] || err "--shortcut-type requires a value"
      case "$1" in
        alias|symlink)
          SHORTCUT_TYPE="$1"
          ;;
        *)
          err "--shortcut-type must be 'alias' or 'symlink'"
          ;;
      esac
      ;;
    --alias-shortcuts)
      SHORTCUT_TYPE="alias"
      ;;
    --symlink-shortcuts)
      SHORTCUT_TYPE="symlink"
      ;;
    --verbose)
      VERBOSE=1
      ;;
    --skip-normalize)
      SKIP_NORMALIZE=1
      ;;
    --skip-humanize)
      SKIP_HUMANIZE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      ;;
  esac
  shift
done

[ -d "$BASE_DIR" ] || err "Base directory not found: $BASE_DIR"
BASE_DIR_ABS="$(cd "$BASE_DIR" && pwd)"
if [ -n "$OUTPUT_ROOT_OVERRIDE" ]; then
  SORTED_DIR_ABS="$(to_abs_path "$OUTPUT_ROOT_OVERRIDE")"
else
  SORTED_DIR_ABS="$BASE_DIR_ABS/$OUTPUT_DIR_NAME"
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SORT_SCRIPT="$SCRIPT_DIR/sort_pokemon_models.sh"
NORMALIZE_SCRIPT="$SCRIPT_DIR/normalize_sorted_names.sh"
HUMANIZE_SCRIPT="$SCRIPT_DIR/humanize_sorted_names.sh"

[ -x "$SORT_SCRIPT" ] || err "Missing executable: $SORT_SCRIPT"
[ -x "$NORMALIZE_SCRIPT" ] || err "Missing executable: $NORMALIZE_SCRIPT"
[ -x "$HUMANIZE_SCRIPT" ] || err "Missing executable: $HUMANIZE_SCRIPT"

if [ -n "$OUTPUT_ROOT_OVERRIDE" ] && [[ "$BASE_DIR_ABS" == "$SORTED_DIR_ABS"/* ]]; then
  if [ "$SKIP_NORMALIZE" -eq 0 ] || [ "$SKIP_HUMANIZE" -eq 0 ]; then
    echo "Output root contains base directory; auto-skipping Stage 2 and Stage 3 for safety."
    echo "Use a dedicated sorted root (or run rename scripts manually on a narrower path) to enable those stages."
    echo "Note: project folder cleanup and shortcut/alias renaming are not applied when these stages are skipped."
    SKIP_NORMALIZE=1
    SKIP_HUMANIZE=1
  fi
fi

echo "Pipeline mode: $MODE"
echo "Base directory: $BASE_DIR_ABS"
echo "Output directory: $SORTED_DIR_ABS"
echo "Transfer mode: $TRANSFER_MODE"
echo "Shortcut type: $SHORTCUT_TYPE"
echo

sort_args=(
  --base-dir "$BASE_DIR_ABS"
  --transfer-mode "$TRANSFER_MODE"
  --shortcut-type "$SHORTCUT_TYPE"
)
if [ -n "$OUTPUT_ROOT_OVERRIDE" ]; then
  sort_args+=(--output-root "$SORTED_DIR_ABS")
else
  sort_args+=(--output-dir "$OUTPUT_DIR_NAME")
fi
if [ "$VERBOSE" -eq 1 ]; then
  sort_args+=(--verbose)
fi

echo "== Stage 1: Sort =="
if [ "$MODE" = "apply" ]; then
  "$SORT_SCRIPT" "${sort_args[@]}" --apply
else
  "$SORT_SCRIPT" "${sort_args[@]}" --dry-run
fi

if [ "$MODE" = "dry-run" ] && [ ! -d "$SORTED_DIR_ABS" ]; then
  echo
  echo "Skipping Stage 2 and Stage 3 in dry-run because output directory does not exist yet:"
  echo "$SORTED_DIR_ABS"
  echo "Run with --apply (or create that output first) to preview downstream rename stages."
  exit 0
fi

if [ "$SKIP_NORMALIZE" -eq 0 ]; then
  echo
  echo "== Stage 2: Normalize =="
  normalize_args=(
    --sorted-dir "$SORTED_DIR_ABS"
    --shortcut-type "$SHORTCUT_TYPE"
  )
  if [ "$VERBOSE" -eq 1 ]; then
    normalize_args+=(--verbose)
  fi
  if [ "$MODE" = "apply" ]; then
    "$NORMALIZE_SCRIPT" "${normalize_args[@]}" --apply
  else
    "$NORMALIZE_SCRIPT" "${normalize_args[@]}" --dry-run
  fi
else
  echo
  echo "== Stage 2: Normalize (skipped) =="
fi

if [ "$SKIP_HUMANIZE" -eq 0 ]; then
  echo
  echo "== Stage 3: Humanize =="
  humanize_args=(
    --sorted-dir "$SORTED_DIR_ABS"
  )
  if [ "$VERBOSE" -eq 1 ]; then
    humanize_args+=(--verbose)
  fi
  if [ "$MODE" = "apply" ]; then
    "$HUMANIZE_SCRIPT" "${humanize_args[@]}" --apply
  else
    "$HUMANIZE_SCRIPT" "${humanize_args[@]}" --dry-run
  fi
else
  echo
  echo "== Stage 3: Humanize (skipped) =="
fi

echo
echo "Pipeline complete."
